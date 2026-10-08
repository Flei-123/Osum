# Dell stability (08.10.2026)

Branch `stab-dell`. Four points from the Dell: a rare #PF panic, the I219 NIC,
the bridge helper eating CPU while idle, and network drop-outs. Every number
below was measured in a VM with `tools/stab/*` (KVM, QEMU; the Dell was not touched).

## 1. Panic: two cores on one kernel stack

Dell panic: `kstate.mode_on -> file.fd_of -> sched.reap -> file.fd_free ->
atomic.lock_take -> cpu.get -> context_switch`, RIP in `.bss`, i.e. a `ret` to
foreign stack content (stack paint `0x5A5A...`).

Root causes found (all in `kernel/sched`, `kernel/ipc/uio.fi`):

* `uio.kill_pid` turned ANY other task into a corpse without the run-queue lock,
  also one that was RUNNING on another core. The parent's `wait4` (or the
  desktop zombie sweep) then reaped it on a third core: stack frames back to the
  allocator and repainted while the victim's core still stood on them.
  Now `sched.kill_other` works under `L_SCHED`: a quiet task becomes a corpse
  right there (children reparented), a RUNNING one only gets `KILL_SET|code` in
  `T_KILLCODE` and ends itself at its next trap/syscall return
  (`signal.deliverable` reports SIGKILL for it).
* The lock-free wake-ups (`wake_pid`, `poll_kick`, `poll_kick_one`,
  `send_task`, timer tick) read `S_WAIT` and stored `S_READY` with two plain
  accesses; in between the sleeper could be running on another core and a third
  core picked it up. Now `sched.state_cas`: the store only happens if the state
  is still the one that was looked at.
* SIGSTOP stored `S_STOP` and switched in two steps (SIGCONT in the gap made a
  running task READY). `sched.stop_sleep` does both under one lock hold.
* `claim_zombie`/`reap_in` only refused the CURRENT task of the calling core;
  now they refuse a corpse that ANY core still runs on (`on_a_core`).
* `wait4` and the zombie sweep called `file.close_all` BEFORE the claim: two
  reapers dropped the same handles twice. `proc.reap` now closes them once,
  after it won the claim.

Test: `tools/stab/crash.sh <boots> <cores> <rounds> <workers> <supervisors>` boots
the VM with fork/exit/wait4/kill churn (`kernel/user/stab.fi`) and counts boots with
an exception or without the end marker.

| series | main 124f9874 | stab-dell |
|---|---|---|
| 4 cores, 4x6x3, 12 boots | 4 crashed + 4 incomplete (8/12 bad) | 0 + 0 |
| 8 cores, 8x14x6 | 11 crashed + 9 incomplete of 20 (20/20 bad) | 0 + 0 of 50 |
| 4 cores, 6x8x4 | - | 0 + 0 of 100 |
| 2 cores, 6x8x3 | - | 0 + 0 of 50 |

The remaining crashes on the old tree were `#UD`/`#GP` at `0x3` / painted
addresses (`rip=0x3`, `rip=0x328f4b`): the same family as the Dell report.

## 2. I219 descriptor-ring flush (`kernel/drv/net/e1000.fi`)

The PCH LAN (I217/I218/I219) can hang on reset when the ring-prefetch engine
still holds descriptors (Linux `e1000e_flush_desc_rings`). Implemented in the
reset path before the GIO master disable: if PCI config `0xE4` bit 8
(`FLUSH_DESC_REQUIRED`) is set, flush TX (dummy descriptor, TDH/TDT) and RX
(RXDCTL prefetch 31 / host 1 / descriptor granularity), then reset.

QEMU has no I219: the kernel word `nicflush` forces the sequence on QEMU's
82574. `tools/stab/flush.sh` checks what a model can show: card still comes up,
TX dummy consumed (TDH = TDT = 1), RXDCTL(0) = `0x0101011f`, nothing printed
without `nicflush`. Result: 6/0. This does not prove the Dell; it proves the
sequence runs and does not break the 82574 path.

## 3. Bridge idle cost (`kernel/app/jarvisd.fi`)

Transport https: every message is its own TCP connection + TLS handshake and an
idle device sends a `puls` per poll. The wait between polls stopped at 2 s
(one handshake every 2 s, for ever) and the root store (PEM parse) was rebuilt
for every request. Now: back-off up to `POLL_MAX_MS` = 5 s (a job resets it at
once) and the root store is parsed once per session.

`tools/stab/net.sh` (private netns, throw-away server + TLS front, fresh device
key, never the Dell's): 60 s idle.

| | connections / min | jarvisd CPU (60 s) |
|---|---|---|
| main 124f9874 | 29.4 | 39 ticks = 0.64 % of a core |
| + poll back-off | 12.0 | 21 ticks = 0.35 % |
| + root store once per session | 12.0 | 17 ticks = 0.28 % |

KVM host; the Dell's CPU is several times slower per handshake, so the saving
there is larger in absolute terms.

## 4. Drop-outs

* DHCP lease was NEVER renewed (`dhcp.fi` took the address once and left). A
  router with a short lease took the address away from a machine that was still
  using it. `dhcp dauer` (already started by the kernel) now renews: RENEWING at
  T1 = lease/2 (unicast), REBINDING at T2 = 7/8 (broadcast), full DISCOVER when
  the lease ends. The address is not touched while renewing (no `osum_netset`),
  so open connections survive. `tools/stab/lease.sh` (T1 shortened to 12 s):
  renewals 0 before / 15 after in 70 s, address set once, lease never lost.
* jarvisd: a failed poll no longer ends the session (the https session lives on
  the server for 12 h): 3 tries first (`POLL_TRIES`). A session that ran at least
  30 s (`GOOD_SESSION_MS`) resets the reconnect back-off, so the first retry
  comes after 250 ms and not after the 30 s an old failure left behind.
* Measured with `net.sh` (QEMU `set_link n0 off` for 40 s, then on):

| | first connection after link-up | first poll of new session |
|---|---|---|
| main 124f9874 | 1.1 s | 1.6 s |
| + poll back-off/retry | 0.8 s | 1.3 s |
| + root store once per session | 1.4 s | 1.9 s |

  This is a 40 s outage with the old tree already back within 2 s, so the test
  does not show a gain there; the difference is within the 5 s poll back-off
  and run-to-run noise. The gain is in the cases it does not cover (lease loss,
  failed single polls, old back-off after a long good session).
* Roadmap N-006 (`SO_KEEPALIVE` does nothing) is NOT done: jarvisd over https
  does not depend on a long-lived TCP connection any more.

## Reproduce

```
/root/jarvis/bin/heavy bash tools/stab/crash.sh 20 8 8 14 6   # KTREE=<old tree> for the counter-series
/root/jarvis/bin/heavy bash tools/stab/flush.sh
/root/jarvis/bin/heavy bash tools/stab/lease.sh               # STAB_TREE=<old tree>
/root/jarvis/bin/heavy bash tools/stab/net.sh 60 40 90        # STAB_TREE=<old tree>, STAB_LABEL=x
```
