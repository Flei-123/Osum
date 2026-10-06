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

Not solved here: in `tools/execsmp/run.sh` (execve variant, 2 runs per boot)
2 of 3 boots end after the first run with `osum: sh exit=-2` and no
`execsmp: children=` for the second run -- the same on main without the fix.
