import bisect
import collections
import os
import re
import struct
import subprocess
import sys

import gdb

REPO = os.environ["HANG_REPO"]
ELF = os.environ["HANG_ELF"]
PORT = os.environ["HANG_PORT"]
MODE = os.environ.get("HANG_MODE", "full")
MAX_FRAMES = 24
SCAN_WORDS = 96
SCAN_KEEP = 10
GROUP_PIDS = 8
FILES = ("kernel/lib/kstate.fi", "kernel/arch/cpu.fi", "kernel/sched/taskconst.fi")
CONST = re.compile(r"^const (\w+): u64 = (0x[0-9A-Fa-f]+|\d+)")
LOCK_NAMES = "SCHED FRAME FS CONSOLE STRESS BOOT NET PROC GUI FD WLQ FQ BUS".split()
STATE_NAMES = "FREE READY RUN SLEEP WAIT ZOMBIE NEW STOP POLL REAPING".split()
KIND_NAMES = "BOOT IDLE WORKER USER GRIND NETD".split()


def load_consts():
    table = {}
    for rel in FILES:
        for line in open(os.path.join(REPO, rel), errors="replace"):
            m = CONST.match(line)
            if m:
                table[m.group(1)] = int(m.group(2), 0)
    return table


def load_symbols():
    text = subprocess.run(["nm", "-n", "--defined-only", ELF], capture_output=True, text=True).stdout
    addrs, names = [], []
    for line in text.splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[1] in "tT":
            addrs.append(int(parts[0], 16))
            names.append(parts[2].replace("_F0.", ""))
    return addrs, names


K = load_consts()
SYM_ADDRS, SYM_NAMES = load_symbols()
TEXT_LO, TEXT_HI = SYM_ADDRS[0], SYM_ADDRS[-1] + 0x10000
OUT = []


def emit(line=""):
    OUT.append(line)


def sym(addr):
    if addr < TEXT_LO or addr >= TEXT_HI:
        return "%#x" % addr
    i = bisect.bisect_right(SYM_ADDRS, addr) - 1
    return "%s+%#x" % (SYM_NAMES[i], addr - SYM_ADDRS[i])


def line_of(addr):
    try:
        sal = gdb.find_pc_line(addr)
        if sal.symtab is not None:
            return "%s:%d" % (sal.symtab.filename, sal.line)
    except gdb.error:
        pass
    return "?"


def read(addr, size):
    try:
        return gdb.selected_inferior().read_memory(addr, size).tobytes()
    except gdb.error:
        return None


def rd64(addr):
    raw = read(addr, 8)
    return struct.unpack("<Q", raw)[0] if raw else None


def reg(name):
    try:
        return int(gdb.parse_and_eval("$" + name)) & 0xFFFFFFFFFFFFFFFF
    except (gdb.error, ValueError, TypeError):
        return None


def kernel_state():
    return int(gdb.parse_and_eval("(long)&kdata")) & 0xFFFFFFFFFFFFFFFF


def frame_chain(rip, rbp):
    chain = [rip]
    seen = 0
    while rbp and seen < MAX_FRAMES:
        pair = read(rbp, 16)
        if not pair:
            break
        nxt, ret = struct.unpack("<QQ", pair)
        if ret < TEXT_LO or ret >= TEXT_HI:
            break
        chain.append(ret)
        if nxt <= rbp:
            break
        rbp = nxt
        seen += 1
    return chain


def stack_scan(rsp):
    raw = read(rsp, SCAN_WORDS * 8)
    if not raw:
        return []
    found = []
    for i in range(SCAN_WORDS):
        v = struct.unpack_from("<Q", raw, i * 8)[0]
        if TEXT_LO <= v < TEXT_HI:
            found.append(v)
        if len(found) >= SCAN_KEEP:
            break
    return found


def task_base(state, slot):
    return state + K["TASK_OFF"] + slot * K["TASK_BYTES"]


def tget(state, slot, field):
    return rd64(task_base(state, slot) + K[field])


def comm_of(state, slot):
    parts = []
    for field in ("T_COMMA", "T_COMMB"):
        v = tget(state, slot, field)
        parts.append(struct.pack("<Q", v or 0).split(b"\0")[0].decode("latin1"))
    return "".join(parts)


def describe_task(state, slot):
    if slot is None or slot >= K["MAX_TASKS"]:
        return "slot=%s" % slot
    return "slot=%d pid=%s %s" % (slot, tget(state, slot, "T_PID"), comm_of(state, slot))


def cpu_field(state, cpu, field):
    return rd64(state + K["CPU_OFF"] + cpu * K["CPU_BYTES"] + K[field])


def cpux_field(state, cpu, field):
    return rd64(state + K["CPUX_OFF"] + cpu * K["CPUX_BYTES"] + K[field])


def dump_vcpus(state):
    inferior = gdb.selected_inferior()
    for thread in sorted(inferior.threads(), key=lambda t: t.num):
        thread.switch()
        rip, rsp, rbp = reg("rip"), reg("rsp"), reg("rbp")
        cs, eflags = reg("cs"), reg("eflags")
        user = cs is not None and (cs & 3) == 3
        emit("VCPU %d rip=%s %s %s rsp=%#x rbp=%#x eflags=%#x IF=%d cs=%#x cr2=%s cr3=%s" % (
            thread.num - 1, "%#x" % (rip or 0), sym(rip or 0), line_of(rip or 0), rsp or 0, rbp or 0,
            eflags or 0, 1 if (eflags or 0) & 0x200 else 0, cs or 0,
            "%#x" % reg("cr2") if reg("cr2") is not None else "?", "%#x" % reg("cr3") if reg("cr3") is not None else "?"))
        if user:
            emit("  user mode")
            continue
        for depth, addr in enumerate(frame_chain(rip, rbp)):
            emit("  F%d %s %s" % (depth, sym(addr), line_of(addr)))
        emit("  scan " + " ".join(sym(a) for a in stack_scan(rsp)))


def dump_cpus(state):
    count = rd64(state + K["SMP_OFF"] + K["SMP_COUNT"]) or 0
    for cpu in range(min(count, 8)):
        cur = cpu_field(state, cpu, "C_CUR")
        emit("CPU %d online=%s cur=(%s) idle=%s ticks=%s switches=%s parked=%s halted=%s pend=%s kicktx=%s kickrx=%s idleent=%#x" % (
            cpu, cpu_field(state, cpu, "C_ONLINE"), describe_task(state, cur), cpu_field(state, cpu, "C_IDLE"),
            cpu_field(state, cpu, "C_TICKS"), cpu_field(state, cpu, "C_SWITCHES"), cpu_field(state, cpu, "C_PARKED"),
            cpux_field(state, cpu, "X_HALTED"), cpux_field(state, cpu, "X_PEND"), cpux_field(state, cpu, "X_KICKTX"),
            cpux_field(state, cpu, "X_KICKRX"), cpux_field(state, cpu, "X_IDLEENT") or 0))


def dump_locks(state):
    for lock_id in range(K["LOCK_COUNT"]):
        base = state + K["LOCK_OFF"] + lock_id * K["LOCK_BYTES"]
        owner, takes, spins = rd64(base), rd64(base + 8), rd64(base + 16)
        who = describe_task(state, owner - 1) if owner else "free"
        emit("LOCK %s owner=%s takes=%s spins=%s" % (LOCK_NAMES[lock_id] if lock_id < len(LOCK_NAMES) else lock_id, who, takes, spins))


def dump_globals(state):
    names = ("TICKS", "SWITCHES", "CURRENT", "TASKS", "NEXT_PID", "PREEMPT", "FRAMES_FREE", "SYSCALLS", "FORKS", "EXECVES")
    emit("GLOBALS " + " ".join("%s=%s" % (n, rd64(state + K[n])) for n in names))


def dump_tasks(state):
    groups = collections.OrderedDict()
    total = rd64(state + K["TASKS"]) or K["MAX_TASKS"]
    for slot in range(min(total + 8, K["MAX_TASKS"])):
        st = tget(state, slot, "T_STATE")
        if not st:
            continue
        rsp = tget(state, slot, "T_RSP")
        chain = [] if st == K["S_RUN"] else stack_scan(rsp)
        sig = (st, tget(state, slot, "T_KIND"), tuple(chain[:SCAN_KEEP]))
        entry = groups.setdefault(sig, [])
        entry.append((slot, tget(state, slot, "T_PID"), tget(state, slot, "T_TGID"), comm_of(state, slot),
                      tget(state, slot, "T_WAKE"), tget(state, slot, "T_FUTEX"), tget(state, slot, "T_TICKS"),
                      tget(state, slot, "T_RUNS"), tget(state, slot, "T_POLLSEQ")))
    for sig, members in sorted(groups.items(), key=lambda kv: -len(kv[1])):
        st, kind, chain = sig
        emit("TASKGROUP n=%d state=%s kind=%s" % (len(members), STATE_NAMES[st] if st < len(STATE_NAMES) else st,
                                                 KIND_NAMES[kind] if kind is not None and kind < len(KIND_NAMES) else kind))
        emit("  chain " + " < ".join(sym(a) for a in chain))
        for slot, pid, tgid, comm, wake, futex, ticks, runs, pollseq in members[:GROUP_PIDS]:
            emit("  slot=%d pid=%s tgid=%s %s wake=%s futex=%#x ticks=%s runs=%s pollseq=%s" % (
                slot, pid, tgid, comm, "%#x" % wake if wake is not None and wake > 1 << 40 else wake,
                futex or 0, ticks, runs, pollseq))
        if len(members) > GROUP_PIDS:
            emit("  ... %d more" % (len(members) - GROUP_PIDS))


def main():
    gdb.execute("set pagination off")
    gdb.execute("set confirm off")
    gdb.execute("file %s" % ELF, to_string=True)
    gdb.execute("target remote :%s" % PORT, to_string=True)
    state = kernel_state()
    emit("HANGDUMP mode=%s state=%#x" % (MODE, state))
    emit(gdb.execute("info threads", to_string=True).rstrip())
    dump_globals(state)
    dump_cpus(state)
    dump_vcpus(state)
    if MODE == "full":
        dump_locks(state)
        dump_tasks(state)
    gdb.execute("detach", to_string=True)
    sys.stdout.write("\n".join(OUT) + "\n")
    sys.stdout.flush()


main()
gdb.execute("quit")
