# Counter-proof helper: adds ONLY the `tray_demo` test keys to an old tree (kernel/user/taskbar.fi) so the old layout can be measured with a fake battery/volume.
# usage: python3 -I demo_patch.py <tree-root>
import sys
p=sys.argv[1]+'/kernel/user/taskbar.fi'
s=open(p,encoding='latin1').read()
def rep(a,b):
    global s
    assert a in s,a
    s=s.replace(a,b,1)
rep('static mut k_group: [u8; 11] = "tray_group\\0"\n','static mut k_group: [u8; 11] = "tray_group\\0"\nstatic mut k_demo: [u8; 11] = "tray_demo\\0\\0"\nstatic mut k_demochg: [u8; 14] = "tray_demochg\\0\\0"\n')
rep('static mut cf_chev: u64 = 0 // tray chevron: icons only <-> the texts\n','static mut cf_chev: u64 = 0 // tray chevron: icons only <-> the texts\nstatic mut cf_demo: u64 = 0\nstatic mut cf_demochg: u64 = 0\n')
old='''            } else if key_is(b + ks, kl, (&k_group[0 as usize]) as u64) {
                if digits > 0 {
                    cf_group = v & 1
                }
'''
rep(old,old+'''            } else if key_is(b + ks, kl, (&k_demo[0 as usize]) as u64) {
                if digits > 0 {
                    cf_demo = clamp(v, 0, 101)
                }
            } else if key_is(b + ks, kl, (&k_demochg[0 as usize]) as u64) {
                if digits > 0 {
                    cf_demochg = v & 1
                }
''')
for a,b in [('let have: u64 = ulib.sys(SYS_PWRGET, PG_BATPRESENT, 0, 0)','let have: u64 = demo_pwr(PG_BATPRESENT)'),('let acv: u64 = ulib.sys(SYS_PWRGET, PG_AC, 0, 0)','let acv: u64 = demo_pwr(PG_AC)'),('let bst: u64 = ulib.sys(SYS_PWRGET, PG_BATSTATE, 0, 0)','let bst: u64 = demo_pwr(PG_BATSTATE)'),('let pc: u64 = ulib.sys(SYS_PWRGET, PG_BATPERCENT, 0, 0)','let pc: u64 = demo_pwr(PG_BATPERCENT)'),('if ulib.sys(SYS_AUDGET, A_READY, 0, 0) == 1 {','if demo_aud(A_READY) == 1 {'),('let v: u64 = ulib.sys(SYS_AUDGET, A_VOLUME, 0, 0)','let v: u64 = demo_aud(A_VOLUME)'),('if ulib.sys(SYS_AUDGET, A_MUTED, 0, 0) == 1 {','if demo_aud(A_MUTED) == 1 {')]:
    rep(a,b)
helper='''fn demo_pwr(what: u64) -> u64 {
    if cf_demo != 0 {
        if what == PG_BATPRESENT {
            return 1
        }
        if what == PG_BATPERCENT {
            return cf_demo - 1
        }
        if what == PG_BATSTATE {
            return cf_demochg * 2
        }
        if what == PG_AC {
            return cf_demochg
        }
    }
    return ulib.sys(SYS_PWRGET, what, 0, 0)
}

fn demo_aud(what: u64) -> u64 {
    if cf_demo != 0 {
        if what == A_READY {
            return 1
        }
        if what == A_VOLUME {
            return cf_demo - 1
        }
        if what == A_MUTED {
            return 0
        }
    }
    return ulib.sys(SYS_AUDGET, what, 0, 0)
}

'''
i=s.index('fn status_build() -> bool {')
lines=s[:i].split('\n'); k=len(lines)-1
while k>0 and lines[k-1].startswith('//'): k-=1
pos=len('\n'.join(lines[:k]))+1
s=s[:pos]+helper+s[pos:]
open(p,'w',encoding='latin1').write(s)
