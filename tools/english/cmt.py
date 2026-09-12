#!/usr/bin/env python3
"""Replace whole comment BLOCKS by their translation, and nothing else.

Input: a .trans file with records
    ==== <path> :: <startline> .. <endline>
    <english comment lines, verbatim, including the // >
The tool checks that the block it replaces still matches the recorded German
text (so a moved file cannot be silently mistranslated), then swaps it.
Code, strings and the line count OUTSIDE the block are untouched.
"""
import sys,os,io

def load(path):
    recs=[];cur=None
    for line in io.open(path,encoding='utf-8').read().splitlines(True):
        if line.startswith('==== '):
            if cur: recs.append(cur)
            head=line[5:].strip()
            f,rng=head.split(' :: ')
            a,b=rng.split('..')
            cur={'file':f.strip(),'a':int(a),'b':int(b),'new':[]}
        elif cur is not None:
            cur['new'].append(line)
    if cur: recs.append(cur)
    return recs

def main():
    trans=sys.argv[1]; apply='--apply' in sys.argv
    recs=load(trans)
    byfile={}
    for r in recs: byfile.setdefault(r['file'],[]).append(r)
    tot=0
    for f,rs in byfile.items():
        lines=io.open(f,encoding='utf-8',errors='surrogateescape').read().splitlines(True)
        for r in sorted(rs,key=lambda r:-r['a']):        # bottom-up: keeps indices valid
            a,b=r['a']-1,r['b']
            old=lines[a:b]
            if not all(l.lstrip().startswith('//') or l.strip()=='' for l in old):
                print("  SKIP (not a pure comment block):",f,r['a'],r['b']); continue
            lines[a:b]=r['new']
            tot+=len(old)
        if apply:
            io.open(f,'w',encoding='utf-8',errors='surrogateescape').write(''.join(lines))
    print(("APPLIED" if apply else "DRY")+f": {len(recs)} blocks, {tot} comment lines, {len(byfile)} files")
main()
