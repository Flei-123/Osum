#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
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
imul rsi,[rdx+88]
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
imul rax,[rdx+88]
mov rsi,[rdx]
lea rsi,[rsi+rax*4]
6:
lea r9,[r8+27520]
mov rax,[rdx+56]
cmp rax,[rdx+32]
jb 7f
sub rax,[rdx+32]
imul rax,[rdx+88]
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
mov rax,[rdx+88]
shl rax,2
add [rdx+8],rax
mov rax,[rdx+56]
inc rax
mov [rdx+56],rax
cmp rax,[rdx+24]
jb 5b
0:
"""

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


def _bcast(reg, scal32):
    return ["movd %s,%s" % (reg, scal32), "pshuflw %s,%s,0" % (reg, reg), "pshufd %s,%s,0" % (reg, reg)]

def _irq_on(flagword):
    return ["mov rax,[r11+%d]" % (flagword * 8), "test rax,rax", "jz 91f", "pushfq", "cli", "91:"]

def _irq_off(flagword):
    return ["mov rax,[r11+%d]" % (flagword * 8), "test rax,rax", "jz 92f", "popfq", "92:"]

def _hash(k):
    L = ["lea rcx,[r10+%d]" % k if k else "mov rcx,r10",
         "imul rcx,rcx,73856093", "xor rcx,[r11+32]", "mov rdx,rcx", "shr rdx,13", "xor rcx,rdx",
         "mov rax,2654435761", "imul rcx,rax", "mov rdx,rcx", "shr rdx,15", "xor rcx,rdx", "mov rsi,rcx",
         "mov rax,[r11+96]", "mul rcx", "mov rax,rsi", "sub rax,rdx", "shr rax,1", "add rax,rdx",
         "mov rcx,[r11+104]", "shr rax,cl", "imul rax,[r11+48]", "sub rsi,rax", "sub rsi,[r11+40]",
         "movzx esi,si", "mov rax,0x0001000100010001", "imul rsi,rax", "mov [r11+%d],rsi" % (128 + 8 * k)]
    return L

def _save(base):
    return ["movdqu [r11+%d],xmm%d" % (base + 16 * k, k) for k in range(16)]

def _restore(base):
    return ["movdqu xmm%d,[r11+%d]" % (k, base + 16 * k) for k in range(16)]

def _s_body():
    L = ["mov r11,rdi", "mov rax,[r11+16]", "shr rax,2", "jz 0f"] + _save(192) + ["mov rdi,rax", "mov r8,[r11]", "mov r9,[r11+8]", "mov r10,[r11+24]"]
    L += _irq_on(15)
    L += ["pxor xmm0,xmm0", "mov rax,[r11+56]"] + _bcast("xmm1", "eax")
    L += ["mov rax,[r11+80]", "mov rcx,[r11+72]", "shl rcx,16", "or rax,rcx", "mov rcx,[r11+64]", "shl rcx,32", "or rax,rcx",
          "movq xmm2,rax", "punpcklqdq xmm2,xmm2"]
    L += ["mov eax,5243"] + _bcast("xmm3", "eax")
    L += ["pcmpeqd xmm4,xmm4", "psrld xmm4,8"]
    L += ["mov rax,[r11+40]", "test rax,rax", "jz 3f", "1:"]
    for k in range(4):
        L += _hash(k)
    simd = ["movdqu xmm6,[r8]", "movdqa xmm7,xmm6", "punpcklbw xmm6,xmm0", "punpckhbw xmm7,xmm0", "pmullw xmm6,xmm1", "pmullw xmm7,xmm1",
            "paddw xmm6,xmm2", "paddw xmm7,xmm2", "pmulhuw xmm6,xmm3", "pmulhuw xmm7,xmm3", "psrlw xmm6,3", "psrlw xmm7,3"]
    tail = ["packuswb xmm6,xmm7", "pand xmm6,xmm4", "movdqu [r9],xmm6", "add r8,16", "add r9,16", "add r10,4", "dec rdi"]
    L += simd + ["movdqu xmm8,[r11+128]", "movdqu xmm9,[r11+144]", "paddw xmm6,xmm8", "paddw xmm7,xmm9"] + tail + ["jnz 1b", "jmp 4f", "3:"]
    L += simd + tail + ["jnz 3b", "4:"]
    L += _irq_off(15)
    L += _restore(192)
    L += ["mov [r11],r8", "mov [r11+8],r9", "mov [r11+24],r10", "mov rax,[r11+16]", "and rax,3", "mov [r11+16],rax", "0:"]
    return "\n".join(L) + "\n"

def _load4(p):
    return ["movd xmm6,[%s]" % p, "movd xmm4,[%s+rcx]" % p, "punpckldq xmm6,xmm4",
            "movd xmm7,[%s+rcx*2]" % p, "movd xmm4,[%s+rdx]" % p, "punpckldq xmm7,xmm4",
            "punpcklbw xmm6,xmm15", "punpcklbw xmm7,xmm15"]

def _norm(src, dst, tmp):
    return ["movdqa %s,%s" % (dst, src), "pmulhuw %s,xmm8" % dst, "movdqa %s,%s" % (tmp, src), "pmullw %s,xmm9" % tmp,
            "paddw %s,%s" % (dst, tmp), "paddw %s,xmm10" % dst, "psrlw %s,3" % dst]

def _consts():
    return (["pxor xmm15,xmm15", "mov eax,4"] + _bcast("xmm10", "eax") + ["pcmpeqd xmm11,xmm11", "psrld xmm11,8"])

def _x_body():
    L = ["mov r11,rdi", "mov rax,[r11+24]", "shr rax,2", "jz 0f", "mov [r11+24],rax", "mov rax,[r11+16]", "test rax,rax", "jz 0f"] + _save(96)
    L += ["mov r8,[r11]", "mov r9,[r11+8]", "mov rcx,[r11+16]", "shl rcx,2", "lea rdx,[rcx+rcx*2]"]
    L += ["1:"] + _irq_on(9) + _consts()
    L += ["pxor xmm0,xmm0", "pxor xmm1,xmm1", "xor eax,eax", "mov [r11+56],rax", "mov [r11+64],rax",
          "mov rsi,r8", "xor r10d,r10d",
          "2:", "cmp r10,[r11+16]", "jae 3f", "cmp r10,[r11+32]", "ja 3f"]
    L += _load4("rsi") + ["paddw xmm0,xmm6", "paddw xmm1,xmm7", "add rsi,4", "inc qword ptr [r11+56]", "inc r10", "jmp 2b", "3:"]
    L += ["xor r10d,r10d", "4:",
          "mov rax,[r11+56]", "cmp rax,[r11+64]", "je 5f", "mov [r11+64],rax", "shl rax,3", "add rax,[r11+40]", "mov rax,[rax]",
          "movzx edi,ax"] + _bcast("xmm8", "edi") + ["shr eax,16"] + _bcast("xmm9", "eax") + ["5:"]
    L += _norm("xmm0", "xmm2", "xmm4") + _norm("xmm1", "xmm3", "xmm5")
    L += ["packuswb xmm2,xmm3", "pand xmm2,xmm11", "lea rax,[r9+r10*4]", "movd [rax],xmm2", "psrldq xmm2,4", "movd [rax+rcx],xmm2",
          "psrldq xmm2,4", "movd [rax+rcx*2],xmm2", "psrldq xmm2,4", "movd [rax+rdx],xmm2"]
    L += ["mov rax,r10", "add rax,[r11+32]", "inc rax", "cmp rax,[r11+16]", "jae 6f", "lea rsi,[r8+rax*4]"]
    L += _load4("rsi") + ["paddw xmm0,xmm6", "paddw xmm1,xmm7", "inc qword ptr [r11+56]", "6:"]
    L += ["cmp r10,[r11+32]", "jb 7f", "mov rax,r10", "sub rax,[r11+32]", "lea rsi,[r8+rax*4]"]
    L += _load4("rsi") + ["psubw xmm0,xmm6", "psubw xmm1,xmm7", "dec qword ptr [r11+56]", "7:"]
    L += ["inc r10", "cmp r10,[r11+16]", "jb 4b"]
    L += _irq_off(9)
    L += ["mov rax,rcx", "shl rax,2", "add r8,rax", "add r9,rax", "mov rax,[r11+24]", "dec rax", "mov [r11+24],rax", "jnz 1b"]
    L += _restore(96) + ["0:"]
    return "\n".join(L) + "\n"

def _w_body():
    L = ["mov r11,rdi", "mov rax,[r11+16]", "test rax,rax", "jz 0f", "mov rax,[r11+24]", "test rax,rax", "jz 0f"] + _save(96)
    L += ["mov r8,[r11+48]", "cld", "xor eax,eax", "mov rdi,r8", "mov rcx,[r11+16]", "rep stosq",
          "lea rdi,[r8+27520]", "mov rcx,[r11+16]", "rep stosq", "xor r10d,r10d", "xor r9d,r9d",
          "1:", "cmp r10,[r11+32]", "ja 4f", "cmp r10,[r11+24]", "jae 4f",
          "mov rsi,r10", "imul rsi,[r11+88]", "mov rax,[r11]", "lea rsi,[rax+rsi*4]"]
    L += _irq_on(10) + ["pxor xmm15,xmm15"]
    L += ["mov rax,r8", "mov rcx,[r11+16]", "shr rcx,2", "2:",
          "movdqu xmm4,[rsi]", "movdqa xmm5,xmm4", "punpcklbw xmm4,xmm15", "punpckhbw xmm5,xmm15",
          "movdqu xmm6,[rax]", "paddw xmm6,xmm4", "movdqu [rax],xmm6", "movdqu xmm7,[rax+16]", "paddw xmm7,xmm5", "movdqu [rax+16],xmm7",
          "add rsi,16", "add rax,32", "dec rcx", "jnz 2b"]
    L += _irq_off(10)
    L += ["inc r9", "inc r10", "jmp 1b", "4:", "mov [r11+64],r9", "xor eax,eax", "mov [r11+56],rax", "5:"]
    L += _irq_on(10) + _consts()
    L += ["mov rax,[r11+40]", "mov rcx,[r11+64]", "mov rax,[rax+rcx*8]", "movzx ecx,ax"]
    L += _bcast("xmm8", "ecx") + ["shr eax,16"] + _bcast("xmm9", "eax")
    L += ["lea rsi,[r8+27520]", "mov rax,[r11+56]", "add rax,[r11+32]", "inc rax", "cmp rax,[r11+24]", "jae 6f",
          "imul rax,[r11+88]", "mov rsi,[r11]", "lea rsi,[rsi+rax*4]", "6:",
          "lea rdi,[r8+27520]", "mov rax,[r11+56]", "cmp rax,[r11+32]", "jb 7f", "sub rax,[r11+32]", "imul rax,[r11+88]",
          "mov rdi,[r11]", "lea rdi,[rdi+rax*4]", "7:", "mov rdx,[r11+8]", "mov rax,r8", "mov rcx,[r11+16]", "shr rcx,2", "3:",
          "movdqu xmm0,[rax]", "movdqu xmm1,[rax+16]"]
    L += _norm("xmm0", "xmm2", "xmm4") + _norm("xmm1", "xmm3", "xmm5")
    L += ["packuswb xmm2,xmm3", "pand xmm2,xmm11", "movdqu [rdx],xmm2",
          "movdqu xmm4,[rsi]", "movdqa xmm5,xmm4", "punpcklbw xmm4,xmm15", "punpckhbw xmm5,xmm15", "paddw xmm0,xmm4", "paddw xmm1,xmm5",
          "movdqu xmm4,[rdi]", "movdqa xmm5,xmm4", "punpcklbw xmm4,xmm15", "punpckhbw xmm5,xmm15", "psubw xmm0,xmm4", "psubw xmm1,xmm5",
          "movdqu [rax],xmm0", "movdqu [rax+16],xmm1", "add rax,32", "add rdx,16", "add rsi,16", "add rdi,16", "dec rcx", "jnz 3b"]
    L += _irq_off(10)
    L += ["mov rax,[r11+56]", "add rax,[r11+32]", "inc rax", "cmp rax,[r11+24]", "jae 8f",
          "mov rax,[r11+64]", "inc rax", "mov [r11+64],rax", "8:",
          "mov rax,[r11+56]", "cmp rax,[r11+32]", "jb 9f", "mov rax,[r11+64]", "dec rax", "mov [r11+64],rax", "9:",
          "mov rax,[r11+88]", "shl rax,2", "add [r11+8],rax", "mov rax,[r11+56]", "inc rax", "mov [r11+56],rax",
          "cmp rax,[r11+24]", "jb 5b"]
    L += _restore(96) + ["0:"]
    return "\n".join(L) + "\n"

S = _s_body()
W = _w_body()
X = _x_body()


BODIES = {"h": H, "v": V, "m": M, "d": D, "g": G, "s": S, "w": W, "x": X}
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
    src = open(os.path.join(root, "kernel/ui/wm/wmblur.fi"), encoding="utf-8").read()
    bad = 0
    if not re.search(r'const BLUR_W_MAX: u64 = 3440\b', src):
        print('MISMATCH: BLUR_W_MAX is not 3440 any more: the row distance 27520 / 55040 in block V must follow'); bad += 1
    for n in BODIES:
        want = embed(n)
        if ('asm("' + want + '"') not in src:
            print("MISMATCH: routine", n, "in kernel/ui/wm/wmblur.fi differs from tools/blur/blurasm.py"); bad += 1
        else:
            print("ok: routine", n)
    return bad

def test():
    here = os.path.dirname(os.path.abspath(__file__))
    d = tempfile.mkdtemp()
    try:
        asm = ".intel_syntax noprefix\n"
        for n in "hvmdgswx":
            asm += ".globl blur_%s_asm\nblur_%s_asm:\npush r12\npush r13\npush r14\npush r15\n%s\npop r15\npop r14\npop r13\npop r12\nret\n" % (n, n, "\n".join(lines(BODIES[n])))
        asm += ".globl xmm_check\nxmm_check:\npush rbx\nmov rbx,rdx\nmov rax,rdi\nmov rdi,rsi\n"
        asm += "".join("movdqu xmm%d,[rcx+%d]\n" % (k, 16 * k) for k in range(16))
        asm += "call rax\n" + "".join("movdqu [rbx+%d],xmm%d\n" % (16 * k, k) for k in range(16)) + "pop rbx\nret\n"
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
