#!/usr/bin/env python3
# entkern.py -- DIE OSUM-FENSTERSCHICHT FUER DAS PROFIL `app`.
#
# wlib/wlibc/ulib/libc sind `profile kernel` (Inline-Assembler erlaubt,
# `syscall` verboten); Certus ist `profile app` (umgekehrt). Das Profil
# haengt an der WURZELDATEI -- ein Programm, das beides bindet, gibt es
# also nicht, solange irgendwo `asm(...)` steht. Dieses Skript macht aus
# den Quellen des Systems Kopien OHNE asm: jeder Assembler-Block wird
# durch den Aufruf einer `extern fn` ersetzt, und dahinter liegen die
# acht Befehlsfolgen in kernel/user/sysstub.s.
#
# Es ist eine MECHANISCHE Umformung mit Kontrolle: findet ein Muster
# nicht genau einmal, bricht das Skript ab. Eine stille Teilumformung
# waere schlimmer als keine.
import sys, os, re

def lies(p):
    return open(p, encoding='utf-8', errors='surrogateescape').read()

def schreib(p, s):
    open(p, 'w', encoding='utf-8', errors='surrogateescape').write(s)

def ersetze(s, alt, neu, wo):
    n = s.count(alt)
    if n != 1:
        print('MUSTER %dx in %s: %r' % (n, wo, alt[:70]), file=sys.stderr)
        sys.exit(1)
    return s.replace(alt, neu)

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
extern fn osum_sock_send(fd: u64, buf: u64, len: u64, addr: u64,
    alen: u64) -> u64;
extern fn osum_sock_recv(fd: u64, buf: u64, len: u64, addr: u64,
    lenp: u64) -> u64;
extern fn osum_aio_submit(op: u64, fd: u64, buf: u64, len: u64,
    ud: u64) -> u64;
'''


def profil_weg(s, wo):
    # `profile kernel` in der ersten Zeile einer importierten Datei ist
    # unter einer app-Wurzel harmlos (prof.rs) -- aber die Datei bekommt
    # hier ohnehin einen neuen Kopf, und der Name des Profils in einer
    # Kopie, die gerade entkernt wurde, waere eine Luege.
    if 'profile kernel\n' in s:
        s = s.replace('profile kernel\n', '// (profile kernel -- entfernt von tools/certus/entkern.py)\n', 1)
    return s


def kcall(s):
    s = profil_weg(s, 'kcall')
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
    s = re.sub(r'fn map_anon\(len: u64, prot: u64, flags: u64\) -> u64 \{\n    let no_fd: u64 = 0 -% 1\n    return asm\([^}]*?\n\}',
               '''fn map_anon(len: u64, prot: u64, flags: u64) -> u64 {
    return osum_map_anon(len, prot, flags)
}''', s, count=1, flags=re.S)
    if 'asm(' in s:
        print('kcall: es steht noch asm( darin', file=sys.stderr)
        sys.exit(1)
    return s + EXT


def wlibc(s):
    s = profil_weg(s, 'wlibc')
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
    if 'asm(' in s:
        print('wlibc: es steht noch asm( darin', file=sys.stderr)
        sys.exit(1)
    return s + EXT


def schlicht(s):
    s = profil_weg(s, '?')
    if 'asm(' in s:
        print('unerwartetes asm(', file=sys.stderr)
        sys.exit(1)
    return s


def main():
    bau = sys.argv[1]
    for name, fn in (('libc/kcall.fi', kcall), ('wlibc.fi', wlibc)):
        p = os.path.join(bau, name)
        schreib(p, fn(lies(p)))
        print('entkernt', name)
    for name in ('ulib.fi', 'wlib.fi', 'icons.fi', 'utf8.fi'):
        p = os.path.join(bau, name)
        if os.path.exists(p):
            schreib(p, schlicht(lies(p)))
    # der Rest der libc: nur das Profil
    d = os.path.join(bau, 'libc')
    for f in sorted(os.listdir(d)):
        if f.endswith('.fi') and f != 'kcall.fi':
            p = os.path.join(d, f)
            schreib(p, schlicht(lies(p)))
    print('fertig')


main()
