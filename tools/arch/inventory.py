#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/arch/inventory.py -- WHAT IS ACTUALLY TIED TO x86-64, COUNTED.

Round ARM, step A. Before anything is moved, the size of the job has to be
a number and not a feeling.

HOW IT COUNTS, and why that way. A first version of this script matched
the whole file text and produced a picture that was too dark: `sys.fi`
came out "machine dependent" because the WORD `syscall` appears in a
comment, and `hw.fi` because it says `IRQ` forty-two times while
describing hardware it never touches. So:

  1. comments are removed first (`//` to end of line, `/* ... */`), and
     string literals are kept -- inline assembly LIVES in a string,
  2. what is counted is not matches but LINES OF CODE that carry a mark,
  3. the number that matters is that line count, not the file size.

The marks:

  asm    inline assembly (`asm("...")`) -- instructions of one machine
  port   the x86 I/O port space (`in`/`out`) -- AArch64 has none at all
  creg   control and system registers (cr0..cr4, MSRs, cpuid, rdtsc)
  desc   the descriptor tables of x86 (lidt/lgdt/ltr, iretq, sysret)
  page   the x86-64 page table format (pml4, pdpt, cr3, invlpg)
  intc   the interrupt controllers of the PC (PIC 8259, PIT 8254, APIC)
  svm    AMD-V / SVM (vmrun, VMCB, NPT) -- no counterpart on AArch64
  mmio   `__mmio_read*`/`__mmio_write*`. As a LANGUAGE construct this is
         machine independent; what is not is the ORDER it promises. It is
         counted and shown, but a file is not called machine dependent
         for it alone -- see docs/ARCH.md, "the weak memory model".

The classes:

  INDEPENDENT  no marked code line at all
  SEAM         1..15 marked code lines: a portable file with a small
               machine seam that step B pulls behind the boundary
  DEPENDENT    more than 15 marked code lines: this IS machine layer
  X86-ONLY     the subject does not exist on AArch64 `-M virt` in that
               form. Named by hand below, with the reason -- a regular
               expression cannot tell "AMD-V" from "some registers".

    ./tools/arch/inventory.py            the table
    ./tools/arch/inventory.py --csv      the same, machine readable
    ./tools/arch/inventory.py --sum      only the summary
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SEAM_LIMIT = 15

MARKS = [
    ("asm", re.compile(r"\basm\(")),
    ("port", re.compile(r"""asm\("\s*(in|out)[bwl]?\s|\b(in|out)(8|16|32)\s*\(|\bport_(read|write)""")),
    ("creg", re.compile(r"\b%?cr[0234]\b|\brdmsr\b|\bwrmsr\b|\bcpuid\b|\brdtscp?\b|\bIA32_|\bEFER\b|\bMSR_|\bxgetbv\b")),
    ("desc", re.compile(r"\blidt\b|\blgdt\b|\bltr\b|\biretq\b|\bsysretq?\b|\bidt_|\bgdt_|\btss_|\bIDT_|\bGDT_|\bTSS_")),
    ("page", re.compile(r"\bpml4|\bpdpt|\b%?cr3\b|\binvlpg\b|\bPTE_|\bPT_PRESENT")),
    ("intc", re.compile(r"\bPIC1\b|\bPIC2\b|\b8259\b|\b8254\b|\bapic_|\bAPIC_|\blapic\b|\bioapic\b|\bLAPIC\b|\bIOAPIC\b|\bmsix?_|\bMSIX?_")),
    ("svm", re.compile(r"\bvmrun\b|\bvmload\b|\bvmsave\b|\bvmcb|\bVMCB|\bsvm_|\bSVM_|\bnpt_|\bNPT_")),
    ("mmio", re.compile(r"__mmio_(read|write)")),
]

# Files whose SUBJECT does not exist on AArch64 `-M virt`, with the reason.
X86_ONLY = {
    "hv.fi": "AMD-V/SVM with a VMCB; the AArch64 counterpart is EL2, a different design",
    "hv.s": "the AMD-V world switch (vmrun/vmload/vmsave) and the guest bodies themselves",
    "vmcb.fi": "the VMCB layout -- an AMD data structure, field for field",
    "ps2m.fi": "the PS/2 auxiliary port at 0x60/0x64; `-M virt` has no keyboard controller",
    "kbd.fi": "the PS/2 keyboard at port 0x60, same chip",
    "acpi.fi": "ACPI tables found through the BIOS/EBDA; `-M virt` describes itself in a device tree",
    "pwr.fi": "IA32_PERF_CTL, HWP, IA32_MISC_ENABLE, monitor/mwait -- Intel MSRs",
    "batt.fi": "battery and mains out of ACPI objects, reached the same way",
    "power.fi": "ACPI shutdown through the PM1 control block in the I/O port space",
    "boot.s": "the Multiboot header and the climb into long mode",
}

# The machine layer proper -- a counterpart exists on the other side, and
# step B is about giving both the same name.
LAYER = {
    "start.s": "startup: stack, page tables, the jump into the kernel",
    "isr.s": "the exception and interrupt entry points",
    "switch.s": "the context switch",
    "smp.s": "the trampoline of the further processors",
    "apic.fi": "the interrupt controller (GIC on AArch64)",
    "idt.fi": "the exception table plus PIC/PIT (VBAR_EL1 plus GIC/CNTV)",
    "trap.fi": "what an exception does once it has arrived",
    "atomic.fi": "atomic operations, barriers, and the lock built on them",
    "cpu.fi": "processor identification",
    "smp.fi": "starting the further processors",
    "time.fi": "the clock and the cycle counter",
    "guard.fi": "SMEP/SMAP (PAN/PXN on AArch64)",
    "mem.fi": "physical frames and the page table format",
    "serial.fi": "the serial console (16550 on x86, PL011 on `-M virt`)",
    "fb.fi": "the frame buffer, reached over the ports 0x1CE/0x1CF",
    "rand.fi": "the entropy source -- cycle counter and timer jitter",
    "proc.fi": "address spaces and the ring change",
    "sched.fi": "the scheduler; its LOGIC is portable, the switch under it is not",
    "user.fi": "the way into ring 3 / EL0",
    "signal.fi": "the signal frame -- a register set of one machine",
    "core.fi": "the minimal kernel of round 52: ports and the VGA text buffer",
    "kcore.fi": "std.core in the kernel, over the same ports",
    "kmain.fi": "the start of the kernel proper",
    "uprog.fi": "the built-in ring 3 programs, assembled in",
    "tasks.fi": "the task bodies of round 59, with `hlt` in them",
    "ansi.fi": "the console, over the serial port",
    "blk.fi": "the block layer: ATA over ports, NVMe over MMIO",
    "nvme.fi": "NVMe -- MMIO plus DMA; the doorbell needs a barrier",
    "pci.fi": "PCI configuration space over the ports 0xCF8/0xCFC",
    "virtio.fi": "virtio over PCI; on `-M virt` the same device is MMIO",
    "wig.fi": "the window calls; the two `asm` lines are the fence pair",
    "wm.fi": "the window server; the two `asm` lines are the fence pair",
    "sys.fi": "the system call gate -- the numbers are Linux', the entry is x86",
    "kstate.fi": "the kernel's own state, including the per-processor block",
    "uio.fi": "copying across the ring boundary",
}

BLOCK = re.compile(r"/\*.*?\*/", re.S)


def strip_comments(text):
    """Comments out, strings kept -- inline assembly lives in a string."""
    text = BLOCK.sub(lambda m: "\n" * m.group(0).count("\n"), text)
    out = []
    for line in text.split("\n"):
        res = []
        i = 0
        instr = False
        quote = ""
        while i < len(line):
            c = line[i]
            if instr:
                if c == "\\":
                    res.append(line[i:i + 2])
                    i += 2
                    continue
                if c == quote:
                    instr = False
                res.append(c)
            elif c in "\"'":
                instr = True
                quote = c
                res.append(c)
            elif c == "/" and i + 1 < len(line) and line[i + 1] == "/":
                break
            elif c in "#;" and line.lstrip().startswith(c) and not res:
                # `#` starts a comment in GNU as source only at line start
                break
            else:
                res.append(c)
            i += 1
        out.append("".join(res))
    return out


def scan(path):
    raw = open(path, "rb").read().decode("utf-8", "replace")
    total = raw.count("\n") + (0 if raw.endswith("\n") else 1)
    code = strip_comments(raw)
    per_mark = {}
    marked = set()
    for i, line in enumerate(code):
        if not line.strip():
            continue
        for name, rx in MARKS:
            if rx.search(line):
                per_mark[name] = per_mark.get(name, 0) + 1
                if name != "mmio":
                    marked.add(i)
    return total, len([l for l in code if l.strip()]), len(marked), per_mark


def classify(base, marked):
    if base in X86_ONLY:
        return "X86-ONLY"
    if marked == 0:
        return "INDEPENDENT"
    if marked <= SEAM_LIMIT:
        return "SEAM"
    return "DEPENDENT"


def rows_of(kdir, prefix=""):
    rows = []
    if not os.path.isdir(kdir):
        return rows
    for f in sorted(os.listdir(kdir)):
        if not (f.endswith(".fi") or f.endswith(".s") or f.endswith(".S")):
            continue
        total, codelines, marked, per = scan(os.path.join(kdir, f))
        rows.append((prefix + f, total, codelines, marked, per,
                     classify(f, marked)))
    return rows


def main():
    # Since round ARM the machine has a directory of its own. Everything in
    # it is machine code by definition, so it is counted apart -- mixing it
    # into the table above would make the boundary look like a failure.
    rows = rows_of(os.path.join(ROOT, "kernel"))
    x86 = rows_of(os.path.join(ROOT, "kernel", "arch", "x86_64"), "arch/x86_64/")
    a64 = rows_of(os.path.join(ROOT, "kernel", "arch", "aarch64"), "arch/aarch64/")
    boundary = rows_of(os.path.join(ROOT, "kernel", "arch"), "arch/")

    if "--csv" in sys.argv:
        print("file,lines,code_lines,machine_lines,class,marks")
        for f, n, c, m, per, cls in rows:
            print("%s,%d,%d,%d,%s,%s" % (f, n, c, m, cls,
                  " ".join("%s=%d" % kv for kv in sorted(per.items()))))
        return

    order = {"INDEPENDENT": 0, "SEAM": 1, "DEPENDENT": 2, "X86-ONLY": 3}
    if "--sum" not in sys.argv:
        print("| file | lines | machine lines | class | marks | what it is |")
        print("|---|---:|---:|---|---|---|")
        for f, n, c, m, per, cls in sorted(rows, key=lambda r: (order[r[5]], -r[3], -r[1])):
            marks = " ".join("%s:%d" % kv for kv in sorted(per.items())) or "--"
            note = X86_ONLY.get(f) or LAYER.get(f) or ""
            print("| `%s` | %d | %d | %s | %s | %s |" % (f, n, m, cls, marks, note))
        print()

    tot, cnt, mach = {}, {}, {}
    for f, n, c, m, per, cls in rows:
        tot[cls] = tot.get(cls, 0) + n
        cnt[cls] = cnt.get(cls, 0) + 1
        mach[cls] = mach.get(cls, 0) + m
    all_lines = sum(tot.values())
    print("| class | files | lines | share of lines | machine lines |")
    print("|---|---:|---:|---:|---:|")
    for cls in ("INDEPENDENT", "SEAM", "DEPENDENT", "X86-ONLY"):
        print("| %s | %d | %d | %.1f %% | %d |" % (cls, cnt.get(cls, 0), tot.get(cls, 0),
              100.0 * tot.get(cls, 0) / all_lines, mach.get(cls, 0)))
    print("| **total** | %d | %d | 100 %% | %d |" %
          (sum(cnt.values()), all_lines, sum(mach.values())))

    def block(title, rr, count_marks=True, note=None):
        if not rr:
            return
        print()
        head = "%s: %d files, %d lines" % (title, len(rr), sum(r[1] for r in rr))
        if count_marks:
            head += ", %d machine lines" % sum(r[3] for r in rr)
        print(head)
        if note:
            print("   (%s)" % note)
        for f, n, c, m, per, cls in sorted(rr, key=lambda r: -r[1]):
            if count_marks:
                print("   %-28s %5d lines, %4d machine lines" % (f, n, m))
            else:
                print("   %-28s %5d lines" % (f, n))

    block("kernel/arch/ (the boundary itself)", boundary)
    block("kernel/arch/x86_64/ (the x86-64 answers)", x86)
    block("kernel/arch/aarch64/ (the AArch64 answers)", a64, count_marks=False,
          note="every line is machine code by construction; the marks this "
               "tool looks for are x86 ones and would read zero here, which "
               "would be a lie by omission rather than a measurement")

    urows = rows_of(os.path.join(ROOT, "kernel", "user"))
    un = sum(r[1] for r in urows)
    um = sum(1 for r in urows if r[3] > 0)
    uml = sum(r[3] for r in urows)
    print()
    print("kernel/user/: %d files, %d lines, %d files with a machine mark, %d machine lines"
          % (len(urows), un, um, uml))
    for f, n, c, m, per, cls in sorted(urows, key=lambda r: -r[3]):
        if m:
            print("   %-16s %5d lines, %3d machine lines  (%s)" % (f, n, m,
                  " ".join("%s:%d" % kv for kv in sorted(per.items()))))


if __name__ == "__main__":
    main()
