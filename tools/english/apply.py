#!/usr/bin/env python3
"""OrientOS German->English identifier rename.

Guarantees:
  * CODE ONLY. String/char literals and comments are byte-identical afterwards
    (asserted per file). Comment translation is a separate, manual pass.
  * Generic names (declared in >1 file) are renamed ONLY inside their declaring
    file -- plus their *qualified* call sites `<thatmodule>.<name>(` elsewhere,
    and their entry in that module's `export { }` list.
"""
import sys,csv,subprocess,collections,re
sys.path.insert(0,'/tmp/en-prep')
from firnlex import rename_code_only, spans

TSV='/tmp/en-prep/rename_final.tsv'
def modname(f): return f.split('/')[-1][:-3]

def targets():
    fs=subprocess.run(['git','ls-files','*.fi'],capture_output=True,text=True).stdout.split()
    return [f for f in fs if not f.startswith('vendor/')]

def build():
    rows=list(csv.DictReader(open(TSV),delimiter='\t'))
    glob={}; own=collections.defaultdict(dict); qual=collections.defaultdict(dict)
    for r in rows:
        o,n=r['old'],r['new']
        if r['scope']=='global': glob[o]=n
        else:
            for d in r['decl_files'].split(';'):
                d=d[2:] if d.startswith('./') else d
                own[d][o]=n
                qual[modname(d)][o]=n     # module.name -> module.newname everywhere
    return rows,glob,own,qual

def apply_qualified(text,qmap):
    """Rename `mod.old` -> `mod.new` in CODE regions only."""
    if not qmap: return text,0
    alt='|'.join(sorted(map(re.escape,qmap),key=len,reverse=True))
    pat=re.compile(r'\b('+alt+r')\.([A-Za-z_][A-Za-z0-9_]*)\b')
    stats={'n':0}
    def sub(m):
        mod,name=m.group(1),m.group(2)
        new=qmap[mod].get(name,name)
        if new!=name: stats['n']+=1
        return mod+'.'+new
    parts=[];cnt=0
    for kind,a,b in spans(text):
        seg=text[a:b]
        if kind=='code':
            seg,_=pat.subn(sub,seg)
        parts.append(seg)
    return ''.join(parts),stats['n']

def main():
    dry='--apply' not in sys.argv
    only=sys.argv[sys.argv.index('--only')+1] if '--only' in sys.argv else None
    rows,glob,own,qual=build()
    files=targets()
    sel=[f for f in files if not only or f.startswith(only)]
    tot=0;touched=0;per={}
    for f in files:
        raw=open(f,encoding='utf-8',errors='surrogateescape').read()
        new=raw;c=0
        # 1. QUALIFIED cross-module references FIRST -- module names are still the
        #    original ones at this point, so `bild.breite` still resolves.
        if qual:
            new,k=apply_qualified(new,qual); c+=k
        # 2. then the identifiers valid in this file (global + this file's generics)
        m=dict(glob); m.update(own.get(f,{}))
        if only and f not in sel: m={}
        if m:
            new,k=rename_code_only(new,m); c+=k
        if c:
            o_s=[raw[a:b] for kk,a,b in spans(raw) if kk in ('str','chr')]
            n_s=[new[a:b] for kk,a,b in spans(new) if kk in ('str','chr')]
            assert o_s==n_s, f"STRING CHANGED in {f}"
            o_c=[raw[a:b] for kk,a,b in spans(raw) if kk=='cmt']
            n_c=[new[a:b] for kk,a,b in spans(new) if kk=='cmt']
            assert o_c==n_c, f"COMMENT CHANGED in {f}"
            tot+=c;touched+=1;per[f]=c
            if not dry: open(f,'w',encoding='utf-8',errors='surrogateescape').write(new)
    print(("DRY RUN" if dry else "APPLIED")+f": {tot} replacements in {touched} files")
    for f,c in sorted(per.items(),key=lambda x:-x[1])[:15]: print(f"  {c:5d}  {f}")
    return per
if __name__=='__main__': main()
