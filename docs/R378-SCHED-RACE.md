# r378: the kernel fell over with two spawns at once (found 06.10.2026)

Symptom: `execsmp run spawn 1 2` (two runs at once), 4 cores, early cores
(`smpfrueh`): in 15-25 % of the boots a #UD/#PF/#GP at a wild rip, rsp on the
kernel stack of a task that sleeps in `wait4`. With 1-2 cores never.

Cause (read in `kernel/sched/sched.fi`): a task goes to sleep in `wait_sleep`
(S_WAIT, under L_SCHED) and calls `schedule_locked`. `wake_pid` (and `poll_kick`)
make a sleeper READY WITHOUT the lock (a decision of their own, they are called
from the net stack and from interrupts). When a child ends on another core
between the state write and `pick`, `pick` finds the sleeper again (its loop
ends at `cur`), `next == cur`, and `schedule_locked` returned with the state
READY although the task kept running on this core. A second core then picked
it ("READY"), loaded the stack pointer of its LAST switch and ran on the same
kernel stack: two cores on one stack, return addresses overwritten
(0xf000ff53 = the BIOS IVT is what a stale pointer reads).

Fix: in the `next == cur` branch the state is set to S_RUN (one line).

Measured (tools/execsmp/crash.sh, KVM):
  before  6 of 24 boots (4 cores), 2 of 12 in the first series
  after   0 of 30 (4 cores), 0 of 20 (3 cores)
Probes that did NOT fire before the fix and so ruled the other ideas out: the
syscall frame lies on the task's own kernel stack; this core's syscall stack is
the current task's; at every switch the saved stack pointer lies inside the
task's own stack. (The stale pointer is inside the stack, only old.)

Other suites on the fixed kernel: smp 60/0, poll 67/0, elfsmp 3/0, s3smp 23/0,
k14 152/0.

Not solved here -- solved afterwards (roadmap r389, see below): in `tools/execsmp/run.sh`
(execve variant, 2 runs per boot) some boots ended after the first run with
`osum: sh exit=-2` and no `execsmp: children=` for the second run, the same on main without the fix.

## The `sh exit=-2` (r389, 06.10.2026): it was not the script

`-2` is `0xFFFFFFFFFFFFFFFE`, the value `kmain.wait_long` returns when its patience ran out --
and that patience was *20 000 rounds of `sleep_ticks(1)`*, which the comment calls 200 seconds.
`sleep_ticks` is a plain `yield_now` while the timer watchdog (`timer_tot`) sees no tick on this
core for a third of a second, which is what four cores do while sixteen children fork and exec at
once (all of them wait for locks with the interrupt flag down). The rounds then run out in well
under two seconds of real time, the kernel stops waiting for `sh`, prints `sh exit=-2` and shuts
down while the second run is still going: 3 of 12 boots (4 cores, KVM), whole boots took 3 s.
Found by looking for the DBG line a patched `wait_for` should have printed (it never came: the
exit was in `wait_long`), then reading what `sleep_ticks` does when the timer is "dead".

Fix: `kutil.give_up_at(state, secs)` / `kutil.gave_up(deadline, rounds, max_rounds)` measure the
wait with the time stamp counter (which does not depend on the timer interrupt) when it has been
measured; `wait_for` (20 s) and `wait_long` (200 s) use them. Without a TSC the old round count
stays. `tools/execsmp/run.sh 4 4 4 2 16`: 16 of 16 boots complete (before 3 of 12 cut), the
counter-proof (`noeargk`) still mixes the argument lists in every boot; `smp` 60/0, `k14` 152/0,
`poll` 67/0, `elfsmp` 3/0.
