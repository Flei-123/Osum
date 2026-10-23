import std.rt
import std.io
import hwinv.dmarparse
import hwinv.report
import hwinv.buf

static mut lits: [u8; 8192] = [0 as u8; 8192]
static mut litn: u64 = 0

fn lit(s: str) -> u64 {
    if litn + (s.n as u64) + 1 > 8192 {
        litn = 0
    }
    let at: u64 = (&lits[0 as usize]) as u64 + litn
    var i: usize = 0
    while i < s.n {
        *((at + i as u64) as *mut u8) = rt.ld8(s.p as u64, i) as u8
        i = i + 1
    }
    *((at + s.n as u64) as *mut u8) = 0 as u8
    litn = litn + (s.n as u64) + 1
    return at
}

fn chk(name: str, cond: bool) {
    if cond {
        io.print("OK   ")
    } else {
        io.print("FAIL ")
    }
    io.print_line(name)
}

fn has_in(p: u64, n: u64, s: str) -> bool {
    return buf.contains(p, n, lit(s))
}

fn rend(i: u64) -> u64 {
    return dmarparse.render(tp(i), (&outb[0 as usize]) as u64, 4096)
}

fn has(i: u64, s: str) -> bool {
    let n: u64 = rend(i)
    return buf.contains((&outb[0 as usize]) as u64, n, lit(s))
}

fn rep(txt: str) -> u64 {
    let d: u64 = lit(txt)
    var n: u64 = 0
    while *((d + n) as *mut u8) != 0 as u8 {
        n = n + 1
    }
    report.feed_dmar(d, n)
    let e: u64 = lit("")
    return report.build(e, 0, e, 0, e, 0, e, 0)
}

fn hasr(s: str) -> bool {
    return buf.contains(buf.out_ptr(), buf.out_len(), lit(s))
}

fn run_all() -> i32 {
    chk("full: ok()", dmarparse.ok(tp(0)))
    chk("full: haw 39", dmarparse.haw(tp(0)) == 39)
    chk("full: 2 drhd", dmarparse.drhd_count(tp(0)) == 2)
    chk("full: 1 rmrr", dmarparse.rmrr_count(tp(0)) == 1)
    chk("full: drhd0 base", dmarparse.drhd_base(tp(0), 0) == 0xFED90000)
    chk("full: drhd1 base", dmarparse.drhd_base(tp(0), 1) == 0xFED91000)
    chk("full: drhd1 include_all", dmarparse.drhd_all(tp(0), 1) && !dmarparse.drhd_all(tp(0), 0))
    chk("full: drhd2 does not exist", dmarparse.drhd_base(tp(0), 2) == 0)
    chk("full: intr_remap flag", dmarparse.intr_remap(tp(0)))
    chk("full: header line", has(0, "dmar: present haw=39 flags=0x05 intr_remap=1 x2apic_optout=0 dma_optin=1 checksum=ok\n"))
    chk("full: drhd0 line", has(0, "dmar: drhd seg=0 base=0xfed90000"))
    chk("full: drhd0 scope", has(0, " include_all=0 scope=pci:00:02.0\n"))
    chk("full: drhd1 include_all", has(0, "base=0xfed91000 include_all=1\n"))
    chk("full: rmrr line", has(0, "dmar: rmrr seg=0 base=0x7a000000 limit=0x7a1fffff scope=pci:00:14.0\n"))
    chk("full: atsr line", has(0, "dmar: atsr seg=0 all_ports=1\n"))
    chk("full: rhsa line", has(0, "dmar: rhsa base=0xfed90000 domain=3\n"))
    chk("full: counts", has(0, "dmar: counts drhd=2 rmrr=1 atsr=1 rhsa=1 other=0\n"))
    chk("empty: ok, no units", dmarparse.ok(tp(1)) && dmarparse.drhd_count(tp(1)) == 0)
    chk("empty: counts all 0", has(1, "dmar: counts drhd=0 rmrr=0 atsr=0 rhsa=0 other=0\n"))
    chk("empty: intr_remap 0", has(1, "intr_remap=0 x2apic_optout=0 dma_optin=0"))
    chk("badsig: not ok", !dmarparse.ok(tp(2)))
    chk("badsig: none line", has(2, "dmar: none\n"))
    chk("badsig: no drhd lines", !has(2, "dmar: drhd"))
    chk("null pointer: none", dmarparse.render(0, (&outb[0 as usize]) as u64, 4096) > 0 && !dmarparse.ok(0))
    chk("badsum: still parsed", dmarparse.drhd_count(tp(3)) == 1)
    chk("badsum: flagged", has(3, "checksum=bad"))
    chk("full: sum ok", !has(0, "checksum=bad"))
    chk("trunc: stops at bad length", dmarparse.drhd_count(tp(4)) == 1)
    chk("trunc: nothing after the bad struct is counted", has(4, "counts drhd=1 rmrr=0 atsr=0 rhsa=0 other=0\n"))
    chk("ioapic scope", has(5, "scope=ioapic:2\n"))
    chk("cap respected", dmarparse.render(tp(0), (&outb[0 as usize]) as u64, 40) < 40)

    rep("dmar: present haw=39 flags=0x03 intr_remap=1 x2apic_optout=1 dma_optin=0 checksum=ok\ndmar: drhd seg=0 base=0xfed90000 include_all=0\ndmar: counts drhd=2 rmrr=1 atsr=0 rhsa=0 other=0\ndmar: unit 0 base=0xfed90000 ver=0x10 cap=0x1c0000c40660462 ecap=0xf0101a translation=off intr_remap=off\ndmar: unit 1 base=0xfed91000 ver=0x10 cap=0x1c0000c40660462 ecap=0xf0101a translation=off intr_remap=off\n")
    chk("report: iommu intel-vtd", hasr("hwinv: iommu=intel-vtd\n"))
    chk("report: units", hasr("hwinv: iommu_units=2\n"))
    chk("report: rmrr", hasr("hwinv: iommu_rmrr=1\n"))
    chk("report: intr_remap", hasr("hwinv: iommu_intr_remap=1\n"))
    chk("report: translation off", hasr("hwinv: iommu_translation=off\n"))
    chk("report: preboot no", hasr("hwinv: iommu_preboot=no\n"))
    chk("report: raw copy", hasr("== dmar ==\ndmar: present"))
    rep("dmar: present haw=39 flags=0x05 intr_remap=1 x2apic_optout=0 dma_optin=1 checksum=ok\ndmar: counts drhd=1 rmrr=0 atsr=0 rhsa=0 other=0\ndmar: unit 0 base=0xfed90000 ver=0x10 cap=0x1 ecap=0x2 translation=on intr_remap=on\n")
    chk("report: translation on", hasr("hwinv: iommu_translation=on\n"))
    chk("report: preboot optin", hasr("hwinv: iommu_preboot=optin\n"))
    chk("report: translation off not claimed", !hasr("iommu_translation=off"))
    rep("dmar: none\n")
    chk("report: none", hasr("hwinv: iommu=none\n"))
    chk("report: none has no units key", !hasr("iommu_units"))
    rep("")
    chk("report: missing file unknown", hasr("hwinv: iommu=unknown\n"))
    chk("report: missing file has no raw section", !hasr("== dmar =="))
    return 0
}
