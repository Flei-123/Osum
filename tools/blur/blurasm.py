#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/blur/blurasm.py -- r464: the three inner loops of the acrylic blur as x86-64 assembly (Intel syntax).
#
#   python3 tools/blur/blurasm.py embed  <name>   print the asm string of one routine the way kernel/ui/wm.fi holds it
#   python3 tools/blur/blurasm.py check           compare the strings in kernel/ui/wm.fi with the text below
#   python3 tools/blur/blurasm.py test            build tools/blur/asmtest.c with gcc and compare against the reference loops
#
# Why: firnc emits stack code with an overflow check on every add (about 15 times slower than C -O2), so the filter
# cost 260 - 390 ns a pixel and one start-menu blur (640 x 416) took 77 - 105 ms. The loops below are the same
# arithmetic (same reciprocal table, same rounding, same hash) in registers.
#
# Every routine takes ONE argument: rdi = pointer to a block of 64-bit words (see the lists) that it also uses as scratch.
# firnc allows only the caller-saved registers rax rcx rdx rsi rdi r8..r11 in an asm block, so the loops keep their
# constants in the block and read them from memory (L1 hits). No calls, no stack use.
import re, subprocess, sys, os, tempfile

H = """
mov rdx,rdi
mov rax,[rdx+24]
test rax,rax
jz 0f
mov rax,[rdx+16]
test rax,rax
jz 0f
1:
xor esi,esi
xor edi,edi
xor r8d,r8d
xor r9d,r9d
xor r10d,r10d
2:
cmp r10,[rdx+16]
jae 3f
cmp r10,[rdx+32]
ja 3f
mov r11,[rdx]
mov eax,[r11+r10*4]
movzx ecx,al
add r8,rcx
mov ecx,eax
shr ecx,8
movzx ecx,cl
add rdi,rcx
shr eax,16
movzx eax,al
add rsi,rax
inc r9
inc r10
jmp 2b
3:
xor r10d,r10d
4:
mov rcx,[rdx+40]
mov rcx,[rcx+r9*8]
mov rax,rsi
imul rax,rcx
add rax,262144
shr rax,19
shl eax,16
mov r11,rdi
imul r11,rcx
add r11,262144
shr r11,19
shl r11d,8
or eax,r11d
mov r11,r8
imul r11,rcx
add r11,262144
shr r11,19
or eax,r11d
mov r11,[rdx+8]
mov [r11+r10*4],eax
mov rax,[rdx+32]
lea rax,[rax+r10+1]
cmp rax,[rdx+16]
jae 5f
mov r11,[rdx]
mov eax,[r11+rax*4]
movzx ecx,al
add r8,rcx
mov ecx,eax
shr ecx,8
movzx ecx,cl
add rdi,rcx
shr eax,16
movzx eax,al
add rsi,rax
inc r9
5:
cmp r10,[rdx+32]
jb 6f
mov rax,r10
sub rax,[rdx+32]
mov r11,[rdx]
mov eax,[r11+rax*4]
movzx ecx,al
sub r8,rcx
mov ecx,eax
shr ecx,8
movzx ecx,cl
sub rdi,rcx
shr eax,16
movzx eax,al
sub rsi,rax
dec r9
6:
inc r10
cmp r10,[rdx+16]
jb 4b
mov rax,[rdx+16]
shl rax,2
add [rdx],rax
add [rdx+8],rax
mov rax,[rdx+24]
dec rax
mov [rdx+24],rax
jnz 1b
0:
"""
# H block: 0 src, 1 dst, 2 w, 3 h, 4 r, 5 reciprocal table (u64 per n); words 0, 1 and 3 are used up (cursors)

V = """
mov rdx,rdi
mov rax,[rdx+24]
test rax,rax
jz 0f
mov rax,[rdx+16]
test rax,rax
jz 0f
mov r8,[rdx+48]
cld
xor eax,eax
mov rdi,r8
mov rcx,[rdx+16]
rep stosq
lea rdi,[r8+27520]
mov rcx,[rdx+16]
rep stosq
lea rdi,[r8+55040]
mov rcx,[rdx+16]
rep stosq
xor r10d,r10d
xor r9d,r9d
1:
cmp r10,[rdx+32]
ja 4f
cmp r10,[rdx+24]
jae 4f
mov rsi,r10
imul rsi,[rdx+16]
mov rax,[rdx]
lea rsi,[rax+rsi*4]
xor edi,edi
2:
mov eax,[rsi+rdi*4]
movzx ecx,al
add [r8+rdi*8+55040],rcx
mov ecx,eax
shr ecx,8
movzx ecx,cl
add [r8+rdi*8+27520],rcx
shr eax,16
movzx eax,al
add [r8+rdi*8],rax
inc rdi
cmp rdi,[rdx+16]
jb 2b
inc r9
inc r10
jmp 1b
4:
xor r10d,r10d
5:
mov rcx,[rdx+40]
mov rcx,[rcx+r9*8]
mov rsi,[rdx+8]
xor edi,edi
6:
mov rax,[r8+rdi*8]
imul rax,rcx
add rax,262144
shr rax,19
shl eax,16
mov r11,[r8+rdi*8+27520]
imul r11,rcx
add r11,262144
shr r11,19
shl r11d,8
or eax,r11d
mov r11,[r8+rdi*8+55040]
imul r11,rcx
add r11,262144
shr r11,19
or eax,r11d
mov [rsi+rdi*4],eax
inc rdi
cmp rdi,[rdx+16]
jb 6b
mov rax,[rdx+32]
lea rax,[r10+rax+1]
cmp rax,[rdx+24]
jae 8f
imul rax,[rdx+16]
mov rsi,[rdx]
lea rsi,[rsi+rax*4]
xor edi,edi
7:
mov eax,[rsi+rdi*4]
movzx ecx,al
add [r8+rdi*8+55040],rcx
mov ecx,eax
shr ecx,8
movzx ecx,cl
add [r8+rdi*8+27520],rcx
shr eax,16
movzx eax,al
add [r8+rdi*8],rax
inc rdi
cmp rdi,[rdx+16]
jb 7b
inc r9
8:
cmp r10,[rdx+32]
jb 3f
mov rax,r10
sub rax,[rdx+32]
imul rax,[rdx+16]
mov rsi,[rdx]
lea rsi,[rsi+rax*4]
xor edi,edi
9:
mov eax,[rsi+rdi*4]
movzx ecx,al
sub [r8+rdi*8+55040],rcx
mov ecx,eax
shr ecx,8
movzx ecx,cl
sub [r8+rdi*8+27520],rcx
shr eax,16
movzx eax,al
sub [r8+rdi*8],rax
inc rdi
cmp rdi,[rdx+16]
jb 9b
dec r9
3:
mov rax,[rdx+16]
shl rax,2
add [rdx+8],rax
inc r10
cmp r10,[rdx+24]
jb 5b
0:
"""
# V block: 0 src, 1 dst, 2 w, 3 h, 4 r, 5 reciprocal table, 6 sum rows (3 rows of u64, 27520 octets apart = BLUR_W_MAX * 8)

M = """
mov r11,rdi
mov rax,[r11+16]
test rax,rax
jz 0f
mov r8,[r11]
mov r9,[r11+8]
mov r10,[r11+24]
1:
mov rcx,[r11+40]
test rcx,rcx
jz 2f
mov rcx,r10
imul rcx,rcx,73856093
xor rcx,[r11+32]
mov rdx,rcx
shr rdx,13
xor rcx,rdx
mov rax,2654435761
imul rcx,rax
mov rdx,rcx
shr rdx,15
xor rcx,rdx
mov rax,rcx
xor edx,edx
mov rcx,[r11+48]
div rcx
sub rdx,[r11+40]
mov [r11+88],rdx
2:
mov eax,[r8]
mov esi,eax
shr esi,16
and esi,255
mov edi,eax
shr edi,8
and edi,255
mov ecx,eax
and ecx,255
imul rsi,[r11+56]
add rsi,[r11+64]
imul rsi,rsi,5243
shr rsi,19
imul rdi,[r11+56]
add rdi,[r11+72]
imul rdi,rdi,5243
shr rdi,19
imul rcx,[r11+56]
add rcx,[r11+80]
imul rcx,rcx,5243
shr rcx,19
mov rdx,[r11+40]
test rdx,rdx
jz 3f
mov rdx,[r11+88]
add rsi,rdx
xor eax,eax
test rsi,rsi
cmovs rsi,rax
mov eax,255
cmp rsi,rax
cmova rsi,rax
add rdi,rdx
xor eax,eax
test rdi,rdi
cmovs rdi,rax
mov eax,255
cmp rdi,rax
cmova rdi,rax
add rcx,rdx
xor eax,eax
test rcx,rcx
cmovs rcx,rax
mov eax,255
cmp rcx,rax
cmova rcx,rax
3:
shl rsi,16
shl rdi,8
or rsi,rdi
or rsi,rcx
mov [r9],esi
add r8,4
add r9,4
inc r10
mov rax,[r11+16]
dec rax
mov [r11+16],rax
jnz 1b
0:
"""
# M block: 0 src, 1 dst, 2 count (used up), 3 x (absolute, first pixel), 4 y * 19349663, 5 amp, 6 2 * amp + 1,
#          7 100 - tint, 8 / 9 / 10 tone red / green / blue * tint, 11 scratch

# r465: one row of the dragged (lifted, scaled) window. Block words: 0 source row, 1 destination, 2 count, 3 first source column q,
# 4 remainder r, 5 whole step qs, 6 remainder step rs, 7 nw. Same stepping as the Firn loop it replaces: sx = (x - ox) * bw / nw.
D = """
mov rdx,rdi
mov rcx,[rdx+16]
test rcx,rcx
jz 0f
mov rsi,[rdx]
mov rdi,[rdx+8]
mov r8,[rdx+24]
mov r9,[rdx+32]
mov r10,[rdx+40]
mov r11,[rdx+48]
1:
mov eax,[rsi+r8*4]
and eax,16777215
mov [rdi],eax
add rdi,4
add r8,r10
add r9,r11
cmp r9,[rdx+56]
jl 2f
sub r9,[rdx+56]
inc r8
2:
dec rcx
jnz 1b
0:
"""

BODIES = {"h": H, "v": V, "m": M, "d": D}
CLOB = ['clobber("rax")', 'clobber("rcx")', 'clobber("rdx")', 'clobber("rsi")', 'clobber("rdi")',
        'clobber("r8")', 'clobber("r9")', 'clobber("r10")', 'clobber("r11")', 'clobber("memory")']

def lines(body):
    return [l for l in body.strip().split("\n") if l]

def firn_string(body):
    return "\\n".join(lines(body))

def embed(name):
    return firn_string(BODIES[name])

def check():
    for n, body in BODIES.items():
        bad = re.findall(r'\b(?:rbx|ebx|rbp|ebp|rsp|esp|r1[2-5][dwb]?)\b', body)
        if bad:
            print('FORBIDDEN register in routine', n, sorted(set(bad))); return 1
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
    src = open(os.path.join(root, "kernel/ui/wm.fi"), encoding="utf-8").read()
    bad = 0
    if not re.search(r'const BLUR_W_MAX: u64 = 3440\b', src):
        print('MISMATCH: BLUR_W_MAX is not 3440 any more: the row distance 27520 / 55040 in block V must follow'); bad += 1
    for n in BODIES:
        want = embed(n)
        if ('asm("' + want + '"') not in src:
            print("MISMATCH: routine", n, "in kernel/ui/wm.fi differs from tools/blur/blurasm.py"); bad += 1
        else:
            print("ok: routine", n)
    return bad

def test():
    here = os.path.dirname(os.path.abspath(__file__))
    d = tempfile.mkdtemp()
    try:
        asm = ".intel_syntax noprefix\n"
        for n in "hvmd":
            asm += ".globl blur_%s_asm\nblur_%s_asm:\npush r12\npush r13\npush r14\npush r15\n%s\npop r15\npop r14\npop r13\npop r12\nret\n" % (n, n, "\n".join(lines(BODIES[n])))
        asm += ".att_syntax prefix\n"
        open(os.path.join(d, "a.S"), "w").write(asm)
        exe = os.path.join(d, "t")
        r = subprocess.run(["gcc", "-O2", "-o", exe, os.path.join(here, "asmtest.c"), os.path.join(d, "a.S")],
                           capture_output=True, text=True)
        if r.returncode:
            print(r.stderr); return 1
        r = subprocess.run([exe])
        return r.returncode
    finally:
        subprocess.run(["rm", "-rf", d])

if __name__ == "__main__":
    c = sys.argv[1] if len(sys.argv) > 1 else ""
    if c == "embed":
        print(embed(sys.argv[2]))
    elif c == "check":
        sys.exit(1 if check() else 0)
    elif c == "test":
        sys.exit(test())
    else:
        print(__doc__)
