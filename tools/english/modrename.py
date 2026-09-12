#!/usr/bin/env python3
"""Module (file) renames: rename the .fi file AND every `import <mod>` /
`<mod>.` reference, in CODE regions only. Comments keep their old text until
the separate comment-translation pass."""
import sys,subprocess,re
sys.path.insert(0,'/tmp/en-prep')
from firnlex import spans

MODMAP={'bild':'image','zeiger':'cursor'}

def rewrite(text,modmap):
    alt='|'.join(sorted(map(re.escape,modmap),key=len,reverse=True))
    imp=re.compile(r'^(\s*import\s+)('+alt+r')(\s*(?:as\s+\w+)?\s*)$',re.M)
    use=re.compile(r'\b('+alt+r')\.')
    parts=[];cnt=0
    for kind,a,b in spans(text):
        seg=text[a:b]
        if kind=='code':
            seg,k1=imp.subn(lambda m:m.group(1)+modmap[m.group(2)]+m.group(3),seg)
            seg,k2=use.subn(lambda m:modmap[m.group(1)]+'.',seg)
            cnt+=k1+k2
        parts.append(seg)
    return ''.join(parts),cnt

def main():
    dry='--apply' not in sys.argv
    files=[f for f in subprocess.run(['git','ls-files','*.fi'],capture_output=True,text=True).stdout.split() if not f.startswith('vendor/')]
    tot=0
    for f in files:
        raw=open(f,encoding='utf-8',errors='surrogateescape').read()
        new,c=rewrite(raw,MODMAP)
        if c:
            tot+=c
            print(f"  {c:3d}  {f}")
            if not dry: open(f,'w',encoding='utf-8',errors='surrogateescape').write(new)
    print(("DRY" if dry else "APPLIED")+f": {tot} module references")
main()
