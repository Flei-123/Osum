#!/usr/bin/env python3
import sys, os, re

def read_2(p):
    return open(p, encoding='utf-8', errors='surrogateescape').read()

def write_2(p, s):
    open(p, 'w', encoding='utf-8', errors='surrogateescape').write(s)

def ersetze(s, alt, new, wo):
    n = s.count(alt)
    if n != 1:
        print('MUSTER %dx in %s: %r' % (n, wo, alt[:70]), file=sys.stderr)
        sys.exit(1)
    return s.replace(alt, new)

EXT = '''
// ==================== RUNDE CERTUS-AUF-OSUM: DIE TUER ALS `extern fn`
// Erzeugt von tools/certus/entkern.py. Die Rümpfe stehen in
// kernel/user/sysstub.s; siehe den Kopf dort.
extern fn osum_sys0(n: u64) -> u64;
extern fn osum_sys1(n: u64, a0: u64) -> u64;
extern fn osum_sys2(n: u64, a0: u64, a1: u64) -> u64;
extern fn osum_sys3(n: u64, a0: u64, a1: u64, a2: u64) -> u64;
extern fn osum_sys4(n: u64, a0: u64, a1: u64, a2: u64, a3: u64) -> u64;
extern fn osum_sys5(n: u64, a0: u64, a1: u64, a2: u64, a3: u64,
    a4: u64) -> u64;
extern fn osum_map_anon(len: u64, prot: u64, flags: u64) -> u64;
extern fn osum_bus5(op: u64, a1: u64, a2: u64, a3: u64, a4: u64) -> u64;
extern fn osum_rdtsc() -> u64;
extern fn osum_map_fd(len: u64, prot: u64, flags: u64, fd: u64, off: u64) -> u64;
extern fn osum_sock_send(fd: u64, buf: u64, len: u64, addr: u64,
    alen: u64) -> u64;
extern fn osum_sock_recv(fd: u64, buf: u64, len: u64, addr: u64,
    lenp: u64) -> u64;
extern fn osum_aio_submit(op: u64, fd: u64, buf: u64, len: u64,
    ud: u64) -> u64;
'''


def profil_gone(s, wo):
    if 'profile kernel\n' in s:
        s = s.replace('profile kernel\n', '// (profile kernel -- entfernt von tools/certus/entkern.py)\n', 1)
    return s


def kcall(s):
    s = profil_gone(s, 'kcall')
    s = ersetze(s, '''fn sys0(number: u64) -> u64 {
    return asm("syscall", out("rax"), in("rax") number, clobber("rcx"),
        clobber("r11"), clobber("memory"))
}''', '''fn sys0(number: u64) -> u64 {
    return osum_sys0(number)
}''', 'kcall.sys0')
    s = ersetze(s, '''fn sys1(number: u64, a0: u64) -> u64 {
    return asm("syscall", out("rax"), in("rax") number, in("rdi") a0,
        clobber("rcx"), clobber("r11"), clobber("memory"))
}''', '''fn sys1(number: u64, a0: u64) -> u64 {
    return osum_sys1(number, a0)
}''', 'kcall.sys1')
    s = ersetze(s, '''fn sys2(number: u64, a0: u64, a1: u64) -> u64 {
    return asm("syscall", out("rax"), in("rax") number, in("rdi") a0,
        in("rsi") a1, clobber("rcx"), clobber("r11"), clobber("memory"))
}''', '''fn sys2(number: u64, a0: u64, a1: u64) -> u64 {
    return osum_sys2(number, a0, a1)
}''', 'kcall.sys2')
    s = ersetze(s, '''fn sys3(number: u64, a0: u64, a1: u64, a2: u64) -> u64 {
    return asm("syscall", out("rax"), in("rax") number, in("rdi") a0,
        in("rsi") a1, in("rdx") a2, clobber("rcx"), clobber("r11"),
        clobber("memory"))
}''', '''fn sys3(number: u64, a0: u64, a1: u64, a2: u64) -> u64 {
    return osum_sys3(number, a0, a1, a2)
}''', 'kcall.sys3')
    s = ersetze(s, '''fn sys4(number: u64, a0: u64, a1: u64, a2: u64, a3: u64) -> u64 {
    return asm("syscall", out("rax"), in("rax") number, in("rdi") a0,
        in("rsi") a1, in("rdx") a2, in("r10") a3, clobber("rcx"),
        clobber("r11"), clobber("memory"))
}''', '''fn sys4(number: u64, a0: u64, a1: u64, a2: u64, a3: u64) -> u64 {
    return osum_sys4(number, a0, a1, a2, a3)
}''', 'kcall.sys4')
    s = re.sub(r'fn aio_submit_call\(op: u64, fd: u64, buf: u64, len: u64, ud: u64\) -> u64 \{\n    return asm\([^}]*?\n\}',
               '''fn aio_submit_call(op: u64, fd: u64, buf: u64, len: u64, ud: u64) -> u64 {
    return osum_aio_submit(op, fd, buf, len, ud)
}''', s, count=1, flags=re.S)
    s = re.sub(r'fn sock_send\(fd: u64, buf: u64, len: u64, addr: u64, alen: u64\) -> u64 \{\n    return asm\([^}]*?\n\}',
               '''fn sock_send(fd: u64, buf: u64, len: u64, addr: u64, alen: u64) -> u64 {
    return osum_sock_send(fd, buf, len, addr, alen)
}''', s, count=1, flags=re.S)
    s = re.sub(r'fn sock_recv\(fd: u64, buf: u64, len: u64, addr: u64, lenp: u64\) -> u64 \{\n    return asm\([^}]*?\n\}',
               '''fn sock_recv(fd: u64, buf: u64, len: u64, addr: u64, lenp: u64) -> u64 {
    return osum_sock_recv(fd, buf, len, addr, lenp)
}''', s, count=1, flags=re.S)
    s = re.sub(r'fn map_fd\(len: u64, prot: u64, flags: u64, fd: u64, off: u64\) -> u64 \{\n    return asm\([^}]*?\n\}',
               '''fn map_fd(len: u64, prot: u64, flags: u64, fd: u64, off: u64) -> u64 {
    return osum_map_fd(len, prot, flags, fd, off)
}''', s, count=1, flags=re.S)
    s = re.sub(r'fn map_anon\(len: u64, prot: u64, flags: u64\) -> u64 \{\n    let no_fd: u64 = 0 -% 1\n    return asm\([^}]*?\n\}',
               '''fn map_anon(len: u64, prot: u64, flags: u64) -> u64 {
    return osum_map_anon(len, prot, flags)
}''', s, count=1, flags=re.S)
    if 'asm(' in s:
        print('kcall: asm( still present', file=sys.stderr)
        sys.exit(1)
    return s + EXT


def wlibc(s):
    s = profil_gone(s, 'wlibc')
    s = wlibc_asm(s)
    return s + EXT


def wlibc_asm(s):
    s = re.sub(r'fn sys5\(number: u64, a0: u64, a1: u64, a2: u64, a3: u64, a4: u64\) -> u64 \{\n    return asm\([^}]*?\n\}',
               '''fn sys5(number: u64, a0: u64, a1: u64, a2: u64, a3: u64, a4: u64) -> u64 {
    return osum_sys5(number, a0, a1, a2, a3, a4)
}''', s, count=1, flags=re.S)
    s = re.sub(r'fn sys3w\(number: u64, a0: u64, a1: u64, a2: u64\) -> u64 \{\n    return asm\([^}]*?\n\}',
               '''fn sys3w(number: u64, a0: u64, a1: u64, a2: u64) -> u64 {
    return osum_sys3(number, a0, a1, a2)
}''', s, count=1, flags=re.S)
    s = re.sub(r'fn map_surface\(bytes: u64\) -> u64 \{\n    let no: u64 = 0 -% 1\n    return asm\([^}]*?\n\}',
               '''fn map_surface(bytes: u64) -> u64 {
    return osum_map_anon(bytes, PROT_RW, MAP_ANON_PRIV)
}''', s, count=1, flags=re.S)
    s = re.sub(r'fn bus5\(op: u64, a1: u64, a2: u64, a3: u64, a4: u64\) -> u64 \{\n    return asm\([^}]*?\n\}',
               '''fn bus5(op: u64, a1: u64, a2: u64, a3: u64, a4: u64) -> u64 {
    return osum_bus5(op, a1, a2, a3, a4)
}''', s, count=1, flags=re.S)
    s = re.sub(r'let p: u64 = asm\("syscall", out\("rax"\), in\("rax"\) SYS_MMAP, in\("rdi"\) 0,\n.*?clobber\("memory"\)\)',
               'let p: u64 = osum_map_fd(bytes, PROT_RW, MAP_SHARED_FLAG, fd, 0)', s, count=1, flags=re.S)
    if 'asm(' in s:
        print('wlibc: asm( still present', file=sys.stderr)
        sys.exit(1)
    return s


def schlicht(s, name='?'):
    s = profil_gone(s, name)
    if name == 'ulib.fi':
        s = re.sub(r'fn bus5\(op: u64, a1: u64, a2: u64, a3: u64, a4: u64\) -> u64 \{\n    return asm\([^}]*?\n\}',
                   '''fn bus5(op: u64, a1: u64, a2: u64, a3: u64, a4: u64) -> u64 {
    return osum_bus5(op, a1, a2, a3, a4)
}''', s, count=1, flags=re.S)
        s += '\nextern fn osum_bus5(op: u64, a1: u64, a2: u64, a3: u64, a4: u64) -> u64;\n'
    if name == 'xfer.fi':
        s = re.sub(r'fn bus5\(op: u64, a1: u64, a2: u64, a3: u64, a4: u64\) -> u64 \{\n    return asm\([^}]*?\n\}',
                   '''fn bus5(op: u64, a1: u64, a2: u64, a3: u64, a4: u64) -> u64 {
    return osum_bus5(op, a1, a2, a3, a4)
}''', s, count=1, flags=re.S)
        s += '\nextern fn osum_bus5(op: u64, a1: u64, a2: u64, a3: u64, a4: u64) -> u64;\n'
    if name == 'wlevent.fi':
        s = s.replace('return asm("rdtsc\\nshl rdx, 32\\nor rax, rdx", out("rax"))', 'return osum_rdtsc()', 1)
        s += '\nextern fn osum_rdtsc() -> u64;\n'
    if name == 'libc/net.fi':
        s = re.sub(r'asm\("syscall", out\("rax"\), in\("rax"\) kcall\.SYS_GETSOCKOPT,.*?clobber\("memory"\)\)',
                   'kcall.sys5(kcall.SYS_GETSOCKOPT, fd, SOL_SOCKET, SO_ERROR, (&val[0]) as u64, (&len[0]) as u64)',
                   s, count=1, flags=re.S)
    if name == 'libc/threads.fi':
        s = re.sub(r'(fn clone_call\([^)]*\) -> u64 \{\n)    return asm\(.*?clobber\("memory"\)\)',
                   r'\1    return 0 -% 38', s, count=1, flags=re.S)
    if 'asm(' in s:
        print('unexpected asm( in ' + name, file=sys.stderr)
        sys.exit(1)
    return s


def split_files(bau, sub):
    d = os.path.join(bau, sub)
    if not os.path.isdir(d):
        return []
    return [os.path.join(d, f) for f in sorted(os.listdir(d))
            if f.endswith('.fi') and os.path.isfile(os.path.join(d, f))]


def main():
    bau = sys.argv[1]
    p = os.path.join(bau, 'libc/kcall.fi')
    write_2(p, kcall(read_2(p)))
    print('entkernt libc/kcall.fi')
    p = os.path.join(bau, 'wlibc.fi')
    write_2(p, profil_gone(read_2(p), 'wlibc'))
    print('entkernt wlibc.fi')
    for p in split_files(bau, 'wlibc'):
        text = profil_gone(read_2(p), os.path.basename(p))
        if os.path.basename(p) == 'wcpaint.fi':
            text = wlibc_asm(text) + EXT
        write_2(p, text)
    for p in split_files(bau, 'uitheme'):
        write_2(p, profil_gone(read_2(p), os.path.basename(p)))
    for p in split_files(bau, 'wlib'):
        write_2(p, schlicht(read_2(p), os.path.basename(p)))
    for name in ('ulib.fi', 'wlib.fi', 'icons.fi', 'utf8.fi'):
        p = os.path.join(bau, name)
        if os.path.exists(p):
            write_2(p, schlicht(read_2(p), name))
    done = ('libc', 'ulib.fi', 'wlib.fi', 'wlibc.fi', 'icons.fi', 'utf8.fi')
    for f in sorted(os.listdir(bau)):
        p = os.path.join(bau, f)
        if f.endswith('.fi') and f not in done and not os.path.islink(p) and os.path.isfile(p) \
                and f not in ('certus_main.fi',):
            write_2(p, schlicht(read_2(p), f))
    d = os.path.join(bau, 'libc')
    for f in sorted(os.listdir(d)):
        if f.endswith('.fi') and f != 'kcall.fi':
            p = os.path.join(d, f)
            write_2(p, schlicht(read_2(p), 'libc/' + f))
    print('fertig')


main()
