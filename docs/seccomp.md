# seccomp / classic BPF

Scope: seccomp filter mode for browser sandboxes (Firefox, Chrome). `bpf()` stays ENOSYS.

## Pieces
- `kernel/sys/seccomp/bpf.fi`: classic BPF validator and interpreter (seccomp subset: W/ABS loads, IMM/MEM/LEN, ST/STX, ALU, JMP, RET K/A, TAX/TXA).
- `kernel/sys/seccomp/filter.fi`: refcounted filter chain blocks (kalloc), attach, TSYNC share, fork inherit, release, strictest-action evaluation.
- `kernel/sys/seccomp/sysseccomp.fi`: `seccomp(2)` (SET_MODE_FILTER, GET_ACTION_AVAIL), `prctl` PR_SET/GET_NO_NEW_PRIVS and PR_SET/GET_SECCOMP, syscall-entry verdicts.

## Behavior
- Task slot field `T_SECCOMP` holds the newest filter block; each block points to the previous one. Fork/clone shares the chain (refcount); reap releases it.
- `dispatch` in `sys.fi` reads `T_SECCOMP` once per syscall; zero means no filter and no further cost.
- All filters of the chain run; the numerically smallest action (signed order) wins.
- Actions: ALLOW, LOG (allow), ERRNO (data capped at 4095), TRAP (SIGSYS, returns ENOSYS), KILL_THREAD (SIGSYS), KILL_PROCESS and unknown (SIGKILL to the thread group), TRACE and USER_NOTIF (ENOSYS).
- Filter flags: TSYNC, LOG, SPEC_ALLOW, TSYNC_ESRCH accepted; NEW_LISTENER rejected with EINVAL.
- Installing needs no_new_privs or euid 0, otherwise EACCES. no_new_privs is inherited and kept across exec.
- Limits: 4096 instructions per filter, invalid programs give EINVAL, bad pointer EFAULT.

## Not done
- Strict mode (`SECCOMP_SET_MODE_STRICT`, `PR_SET_SECCOMP` mode 1) returns EINVAL.
- SIGSYS siginfo fields (si_syscall, si_arch, si_call_addr) are not filled in.
- SECCOMP_RET_USER_NOTIF and SECCOMP_RET_TRACE have no supervisor.
