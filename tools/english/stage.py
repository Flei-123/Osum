#!/usr/bin/env python3
"""Apply ONE stage of the rename. Usage: stage.py <STAGE> [--apply]

A stage is a subset of tools/english/rename_final.tsv, chosen by where the
renamed function is DECLARED. Every stage is applied to the whole tree,
because a function declared in kernel/ is called from everywhere.

Guarantees, checked per file and aborting on violation:
  * only code regions change; string/char literals and comments stay byte-equal
  * generic names (declared in >1 file) change only inside their own file,
    plus that module's qualified `mod.name(` call sites and export list
"""
import sys,csv,subprocess,collections,re,os
HERE=os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0,HERE)
from firnlex import rename_code_only, spans

TSV=os.path.join(HERE,'rename_final.tsv')
LAST={'./kernel/user/wlib.fi','./kernel/user/wlibc.fi','./kernel/user/taskbar.fi','./kernel/user/fuib.fi'}

def group(files):
    fs=files.split(';')
    if any(f in LAST for f in fs): return 'Z-LAST'
    f=fs[0]
    if f.startswith('./kernel/app/'): return 'E3-app'
    if f.startswith('./kernel/user/'): return 'E4-user'
    if f.startswith('./kernel/'): return 'E2-kernel'
    if f.startswith(('./lib/','./module/','./tools/')): return 'E1-lib'
    return 'E5-other'

def modname(f): return f.split('/')[-1][:-3]

def build(stage):
    all_rows=list(csv.DictReader(open(TSV),delimiter='\t'))
    if stage.startswith('FILE:'):
        # one single declaring file at a time -- used for the four reserved
        # files (wlib, wlibc, taskbar, fuib), which come last and separately.
        want=stage[5:]
        rows=[r for r in all_rows if want in r['decl_files'].split(';')]
    else:
        rows=[r for r in all_rows if group(r['decl_files'])==stage]
    glob={}; own=collections.defaultdict(dict); qual=collections.defaultdict(dict)
    for r in rows:
        o,n=r['old'],r['new']
        if r['scope']=='global': glob[o]=n
        else:
            for d in r['decl_files'].split(';'):
                d=d[2:] if d.startswith('./') else d
                own[d][o]=n
                qual[modname(d)][o]=n
    return rows,glob,own,qual

def apply_qualified(text,qmap):
    if not qmap: return text,0
    alt='|'.join(sorted(map(re.escape,qmap),key=len,reverse=True))
    pat=re.compile(r'\b('+alt+r')\.([A-Za-z_][A-Za-z0-9_]*)\b')
    st={'n':0}
    def sub(m):
        mod,name=m.group(1),m.group(2)
        new=qmap[mod].get(name,name)
        if new!=name: st['n']+=1
        return mod+'.'+new
    parts=[]
    for kind,a,b in spans(text):
        seg=text[a:b]
        if kind=='code': seg,_=pat.subn(sub,seg)
        parts.append(seg)
    return ''.join(parts),st['n']

def main():
    stage=sys.argv[1]
    dry='--apply' not in sys.argv
    rows,glob,own,qual=build(stage)
    files=[f for f in subprocess.run(['git','ls-files','*.fi'],capture_output=True,text=True).stdout.split()
           if not f.startswith('vendor/')]
    tot=0;per={}
    for f in files:
        raw=open(f,encoding='utf-8',errors='surrogateescape').read()
        new,c=apply_qualified(raw,qual)          # trap 2: qualified pass FIRST
        m=dict(glob); m.update(own.get(f,{}))
        if m:
            new,k=rename_code_only(new,m); c+=k
        if c:
            o_s=[raw[a:b] for k2,a,b in spans(raw) if k2 in ('str','chr')]
            n_s=[new[a:b] for k2,a,b in spans(new) if k2 in ('str','chr')]
            assert o_s==n_s, "STRING LITERAL MOVED in "+f
            o_c=[raw[a:b] for k2,a,b in spans(raw) if k2=='cmt']
            n_c=[new[a:b] for k2,a,b in spans(new) if k2=='cmt']
            assert o_c==n_c, "COMMENT MOVED in "+f
            tot+=c;per[f]=c
            if not dry: open(f,'w',encoding='utf-8',errors='surrogateescape').write(new)
    print(f"{'DRY' if dry else 'APPLIED'} {stage}: {len(rows)} names, {tot} replacements in {len(per)} files")
    for f,c in sorted(per.items(),key=lambda x:-x[1])[:10]: print(f"   {c:5d}  {f}")
main()
