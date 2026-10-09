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
mov rsi,[rdx]
mov rdi,[rdx+8]
1:
xor r8d,r8d
xor r9d,r9d
xor r10d,r10d
2:
cmp r10,[rdx+16]
jae 3f
cmp r10,[rdx+32]
ja 3f
mov eax,[rsi+r10*4]
mov ecx,eax
and ecx,16711935
and eax,65280
shl rax,24
or rax,rcx
add r8,rax
inc r9
inc r10
jmp 2b
3:
xor r10d,r10d
4:
mov rcx,[rdx+40]
mov rcx,[rcx+r9*8]
mov rax,r8
movzx eax,ax
imul rax,rcx
add rax,262144
shr rax,19
mov r11,r8
shr r11,16
movzx r11d,r11w
imul r11,rcx
add r11,262144
shr r11,19
shl r11d,16
or eax,r11d
mov r11,r8
shr r11,32
movzx r11d,r11w
imul r11,rcx
add r11,262144
shr r11,19
shl r11d,8
or eax,r11d
mov [rdi+r10*4],eax
mov rax,[rdx+32]
lea rax,[rax+r10+1]
cmp rax,[rdx+16]
jae 5f
mov eax,[rsi+rax*4]
mov ecx,eax
and ecx,16711935
and eax,65280
shl rax,24
or rax,rcx
add r8,rax
inc r9
5:
cmp r10,[rdx+32]
jb 6f
mov rax,r10
sub rax,[rdx+32]
mov eax,[rsi+rax*4]
mov ecx,eax
and ecx,16711935
and eax,65280
shl rax,24
or rax,rcx
sub r8,rax
dec r9
6:
inc r10
cmp r10,[rdx+16]
jb 4b
mov rax,[rdx+16]
shl rax,2
add rsi,rax
add rdi,rax
mov rax,[rdx+24]
dec rax
mov [rdx+24],rax
jnz 1b
0:
"""
# H block: 0 src, 1 dst, 2 w, 3 h, 4 r, 5 reciprocal table (u64 per n); words 3 is used up (row counter). The running sum of a
# row is ONE register, three 16-bit lanes (blue at bit 0, red at 16, green at 32: a lane holds at most 255 * 39 = 9945, so
# nothing carries into the next lane, and the sum minus a pixel never goes below zero): adding / removing a pixel is
# ((p & 0x00FF00FF) | ((p & 0xFF00) << 24)) and one add / sub. The arithmetic of the output is the one of the old loop.

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
mov ecx,eax
and ecx,16711935
and eax,65280
shl rax,24
or rax,rcx
add [r8+rdi*8],rax
inc rdi
cmp rdi,[rdx+16]
jb 2b
inc r9
inc r10
jmp 1b
4:
mov [rdx+64],r9
xor eax,eax
mov [rdx+56],rax
5:
mov rax,[rdx+40]
mov rcx,[rdx+64]
mov rax,[rax+rcx*8]
mov [rdx+72],rax
mov rax,[rdx+56]
add rax,[rdx+32]
inc rax
lea rsi,[r8+27520]
cmp rax,[rdx+24]
jae 6f
imul rax,[rdx+16]
mov rsi,[rdx]
lea rsi,[rsi+rax*4]
6:
lea r9,[r8+27520]
mov rax,[rdx+56]
cmp rax,[rdx+32]
jb 7f
sub rax,[rdx+32]
imul rax,[rdx+16]
mov r9,[rdx]
lea r9,[r9+rax*4]
7:
mov r10,[rdx+8]
xor edi,edi
8:
mov rax,[r8+rdi*8]
movzx ecx,ax
imul rcx,[rdx+72]
add rcx,262144
shr rcx,19
mov r11,rax
shr r11,16
movzx r11d,r11w
imul r11,[rdx+72]
add r11,262144
shr r11,19
shl r11d,16
or ecx,r11d
shr rax,32
movzx eax,ax
imul rax,[rdx+72]
add rax,262144
shr rax,19
shl eax,8
or eax,ecx
mov [r10+rdi*4],eax
mov rax,[r8+rdi*8]
mov ecx,[rsi+rdi*4]
mov r11d,ecx
and ecx,16711935
and r11d,65280
shl r11,24
or rcx,r11
add rax,rcx
mov ecx,[r9+rdi*4]
mov r11d,ecx
and ecx,16711935
and r11d,65280
shl r11,24
or rcx,r11
sub rax,rcx
mov [r8+rdi*8],rax
inc rdi
cmp rdi,[rdx+16]
jb 8b
mov rax,[rdx+56]
add rax,[rdx+32]
inc rax
cmp rax,[rdx+24]
jae 9f
mov rax,[rdx+64]
inc rax
mov [rdx+64],rax
9:
mov rax,[rdx+56]
cmp rax,[rdx+32]
jb 3f
mov rax,[rdx+64]
dec rax
mov [rdx+64],rax
3:
mov rax,[rdx+16]
shl rax,2
add [rdx+8],rax
mov rax,[rdx+56]
inc rax
mov [rdx+56],rax
cmp rax,[rdx+24]
jb 5b
0:
"""
# V block: 0 src, 1 dst, 2 w, 3 h, 4 r, 5 reciprocal table, 6 sum row (w words, three 16-bit lanes like block H; the row 27520 octets =
# BLUR_W_MAX * 8 further on is a row of zeros), 7 scratch, 8 scratch (words 7 - 9 of the block are used as scratch: 7 = row y, 8 = n, 9 = reciprocal;
# the block has 12 words). ONE pass per output row: normalise the sums of the row into the destination, then add the incoming row and remove the
# outgoing one (a row of zeros when there is none) -- the old code made three passes over 24 octets per pixel.

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
mov rsi,rcx
mov rax,[r11+96]
mul rcx
mov rax,rsi
sub rax,rdx
shr rax,1
add rax,rdx
mov rcx,[r11+104]
shr rax,cl
imul rax,[r11+48]
sub rsi,rax
sub rsi,[r11+40]
mov [r11+88],rsi
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

# r466: the modulus of the grain (v % (2 * amp + 1), a 64-bit `div` per pixel, 25 - 40 cycles) as a multiplication. Block word 6 = d (odd, >= 3);
# the routine writes the magic number (word 12) and the shift (word 13) once per blur; the loop M then does q = ((v - hi) >> 1 + hi) >> shift with
# hi = high word of magic * v and v - q * d (the libdivide "65-bit" way; checked against `%` in tools/blur/asmtest.c).
G = """
mov r11,rdi
mov rcx,[r11+48]
cmp rcx,3
jb 0f
bsr rcx,rcx
mov [r11+104],rcx
mov edx,1
shl rdx,cl
xor eax,eax
mov rsi,[r11+48]
div rsi
mov rdi,rdx
add rax,rax
add rdi,rdi
jc 1f
cmp rdi,rsi
jb 2f
1:
inc rax
2:
inc rax
mov [r11+96],rax
0:
"""
# G block: the M block (16 words): 6 = d in, 12 = magic out, 13 = shift out

BODIES = {"h": H, "v": V, "m": M, "d": D, "g": G}
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
        for n in "hvmdg":
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
